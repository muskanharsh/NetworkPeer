import { randomInt, timingSafeEqual } from "node:crypto";
import { PublishCommand, SNSClient } from "@aws-sdk/client-sns";

const snsDefault = new SNSClient({});
const snsMumbai = new SNSClient({ region: "ap-south-1" });

const otpLength = Number(process.env.OTP_LENGTH ?? "6");
const maxAttempts = Number(process.env.OTP_MAX_ATTEMPTS ?? "5");
const ttlMinutes = Number(process.env.OTP_TTL_MINUTES ?? "5");
const messageTemplate = process.env.OTP_MESSAGE_TEMPLATE ?? "Your NetworkPeer verification code is {code}.";
const fast2SmsKey = process.env.FAST2SMS_API_KEY || process.env.FAST2SMS_KEY;
const twoFactorKey = process.env.TWO_FACTOR_API_KEY || process.env.TWO_FACTOR_KEY;

function isE164(value) {
  return typeof value === "string" && /^\+[1-9]\d{1,14}$/.test(value);
}

function generateOtp() {
  return randomInt(0, 10 ** otpLength).toString().padStart(otpLength, "0");
}

function sameValue(expected, actual) {
  if (typeof expected !== "string" || typeof actual !== "string") return false;
  const expectedBuffer = Buffer.from(expected);
  const actualBuffer = Buffer.from(actual);
  return expectedBuffer.length === actualBuffer.length && timingSafeEqual(expectedBuffer, actualBuffer);
}

function otpMessage(otp) {
  return messageTemplate
    .replaceAll("{code}", otp)
    .replaceAll("{minutes}", String(ttlMinutes));
}

async function sendViaFast2SMS(phoneNumber, otp) {
  const digits = phoneNumber.replace(/\D/g, "");
  const tenDigits = digits.slice(-10);
  console.log(`[FAST2SMS] Dispatching OTP to ${tenDigits}...`);

  const otpId = process.env.FAST2SMS_OTP_ID;
  if (otpId) {
    // Fast2SMS Smart OTP Endpoint
    const url = "https://www.fast2sms.com/dev/otp/send";
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": fast2SmsKey,
        "Content-Type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify({
        otp_id: otpId,
        mobile: tenDigits,
        otp: otp,
      }),
    });
    const data = await res.json();
    console.log(`[FAST2SMS_SMART_OTP_RESULT] Status: ${res.status}`);
    if (!res.ok || data.return !== true) {
      throw new Error(`Fast2SMS Smart OTP failed with status ${res.status}: ${data.message || JSON.stringify(data)}`);
    }
    return data;
  }

  // Fallback: Bulk V2 Route
  const url = `https://www.fast2sms.com/dev/bulkV2?authorization=${encodeURIComponent(fast2SmsKey)}&route=otp&variables_values=${encodeURIComponent(otp)}&flash=0&numbers=${encodeURIComponent(tenDigits)}`;
  const res = await fetch(url, {
    method: "GET",
    headers: { "cache-control": "no-cache" },
  });
  const data = await res.json();
  console.log(`[FAST2SMS_RESULT] Status: ${res.status}`);
  if (!res.ok || data.return !== true) {
    throw new Error(`Fast2SMS failed with status ${res.status}: ${data.message || JSON.stringify(data)}`);
  }
  return data;
}

async function sendVia2Factor(phoneNumber, otp) {
  const digits = phoneNumber.replace(/\D/g, "");
  const tenDigits = digits.slice(-10);
  console.log(`[2FACTOR] Dispatching OTP to ${tenDigits}...`);
  const url = `https://2factor.in/API/V1/${encodeURIComponent(twoFactorKey)}/SMS/${encodeURIComponent(tenDigits)}/${encodeURIComponent(otp)}/AUTOGEN`;
  const res = await fetch(url);
  const data = await res.json();
  console.log(`[2FACTOR_RESULT] Status: ${res.status}`);
  if (!res.ok || data.Status !== "Success") {
    throw new Error(`2Factor failed with status ${res.status}: ${data.Details || JSON.stringify(data)}`);
  }
  return data;
}

async function sendViaSns(phoneNumber, otp) {
  const messageAttributes = {
    "AWS.SNS.SMS.SMSType": { DataType: "String", StringValue: "Transactional" },
  };
  if (process.env.OTP_SNS_SENDER_ID) {
    messageAttributes["AWS.SNS.SMS.SenderID"] = {
      DataType: "String",
      StringValue: process.env.OTP_SNS_SENDER_ID,
    };
  }
  if (process.env.OTP_SNS_ORIGINATION_NUMBER) {
    messageAttributes["AWS.SNS.SMS.OriginationNumber"] = {
      DataType: "String",
      StringValue: process.env.OTP_SNS_ORIGINATION_NUMBER,
    };
  }

  const isIndia = phoneNumber.startsWith("+91");
  const useMumbai = isIndia && process.env.USE_SNS_MUMBAI === "true";
  const client = useMumbai ? snsMumbai : snsDefault;
  const region = useMumbai ? "ap-south-1" : (process.env.AWS_REGION || "eu-north-1");

  console.log(`[AWS_SNS] Dispatching SMS via ${region} to ${phoneNumber}...`);
  const result = await client.send(new PublishCommand({
    PhoneNumber: phoneNumber,
    Message: otpMessage(otp),
    MessageAttributes: messageAttributes,
  }));
  console.log(`[AWS_SNS_RESULT] MessageId: ${result.MessageId}`);
  return result;
}

async function sendOtp(phoneNumber, otp) {
  // Route 1: Fast2SMS Quick OTP Gateway (Pre-approved Indian DLT Route)
  if (fast2SmsKey && phoneNumber.startsWith("+91")) {
    try {
      await sendViaFast2SMS(phoneNumber, otp);
      return;
    } catch (err) {
      console.error("[FAST2SMS_ERROR] Fast2SMS delivery failed, trying fallback:", err?.message || err);
    }
  }

  // Route 2: 2Factor Gateway
  if (twoFactorKey && phoneNumber.startsWith("+91")) {
    try {
      await sendVia2Factor(phoneNumber, otp);
      return;
    } catch (err) {
      console.error("[2FACTOR_ERROR] 2Factor delivery failed, trying fallback:", err?.message || err);
    }
  }

  // Route 3: AWS SNS (eu-north-1 or ap-south-1)
  try {
    await sendViaSns(phoneNumber, otp);
  } catch (err) {
    console.error("[AWS_SNS_ERROR] SNS delivery failed:", err?.message || err);
    // Intentionally catch to allow Cognito challenge creation to proceed.
  }
}

function defineChallenge(event) {
  const challenges = event.request.session ?? [];
  const customChallenges = challenges.filter((challenge) => challenge.challengeName === "CUSTOM_CHALLENGE");
  const lastChallenge = customChallenges.at(-1);

  if (lastChallenge?.challengeResult === true) {
    event.response.issueTokens = true;
    event.response.failAuthentication = false;
    return event;
  }

  if (customChallenges.length >= maxAttempts) {
    event.response.issueTokens = false;
    event.response.failAuthentication = true;
    return event;
  }

  event.response.issueTokens = false;
  event.response.failAuthentication = false;
  event.response.challengeName = "CUSTOM_CHALLENGE";
  return event;
}

async function createChallenge(event) {
  const phoneNumber = event.request.userAttributes?.phone_number;
  if (!isE164(phoneNumber)) throw new Error("Cognito user does not have a valid E.164 phone number");

  const otp = generateOtp();
  await sendOtp(phoneNumber, otp);
  event.response.publicChallengeParameters = {
    delivery: "sms",
    otp_length: String(otpLength),
  };
  event.response.privateChallengeParameters = { answer: otp };
  event.response.challengeMetadata = "NETWORKPEER_OTP";
  return event;
}

function verifyChallenge(event) {
  const answer = event.request.challengeAnswer?.trim();
  const expected = event.request.privateChallengeParameters?.answer;

  const isCorrectOtp = sameValue(expected, answer);
  event.response.answerCorrect = isCorrectOtp;
  console.log(`[AUTH_OTP_VERIFY] ${isCorrectOtp ? "accepted" : "rejected"}`);
  return event;
}

export const handler = async (event) => {
  switch (event.triggerSource) {
    case "DefineAuthChallenge_Authentication":
      return defineChallenge(event);
    case "CreateAuthChallenge_Authentication":
      return createChallenge(event);
    case "VerifyAuthChallengeResponse_Authentication":
      return verifyChallenge(event);
    default:
      throw new Error(`Unsupported Cognito trigger source: ${event.triggerSource}`);
  }
};
