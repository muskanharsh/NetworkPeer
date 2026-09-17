import Fastify from "fastify";
import cookie from "@fastify/cookie";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { issueTestCognitoAccessToken, resetTestCognitoVerifier } from "../src/testing/cognito-test-verifier.js";

const refundClientJob = vi.hoisted(() => vi.fn());
const getUserByCognitoSub = vi.hoisted(() => vi.fn());
const adminOverrideJob = vi.hoisted(() => vi.fn());
const adminSuspendUser = vi.hoisted(() => vi.fn());
const getUserById = vi.hoisted(() => vi.fn());
const getAdminAnalytics = vi.hoisted(() => vi.fn());
const listAdminAuditLog = vi.hoisted(() => vi.fn());
const listAdminUsers = vi.hoisted(() => vi.fn());
const updateWorkerVerificationAsAdmin = vi.hoisted(() => vi.fn());

vi.mock("../src/repository.js", () => ({
  refundClientJob,
  getUserByCognitoSub,
  adminOverrideJob,
  adminSuspendUser,
  getUserById,
  getAdminAnalytics,
  listAdminAuditLog,
  listAdminUsers,
  updateWorkerVerificationAsAdmin,
}));

import adminRoutes from "../src/routes/admin.js";
import { config } from "../src/config.js";

const ADMIN_ID = "00000000-0000-4000-8000-000000000001";
const CLIENT_ID = "00000000-0000-4000-8000-000000000002";
const JOB_ID = "00000000-0000-4000-8000-0000000000aa";
const REFUND_TXN_ID = "00000000-0000-4000-8000-0000000000bb";

let app: ReturnType<typeof Fastify> | undefined;

/** Shapes a pg error the way node-postgres surfaces a RAISE ... USING ERRCODE. */
function pgError(code: string, message = "database rejected the operation"): Error & { code: string } {
  return Object.assign(new Error(message), { code });
}

function refundedJob(previousStatus: string) {
  return {
    id: JOB_ID,
    client_id: CLIENT_ID,
    worker_id: null,
    status: "CANCELLED",
    escrow_status: "REFUNDED",
    previous_status: previousStatus,
    budget_cents: 45_000,
    currency: "INR",
  };
}

async function buildTestApp() {
  const testApp = Fastify();
  await testApp.register(cookie);
  await testApp.register(adminRoutes, { prefix: config.API_PREFIX });
  await testApp.ready();
  return testApp;
}

function adminToken(): string {
  return issueTestCognitoAccessToken({ id: ADMIN_ID, phone: "+15550000001", role: "ADMIN" });
}

function refundRequest(token: string, body: Record<string, unknown> = {}) {
  return {
    method: "POST" as const,
    url: `${config.API_PREFIX}/admin/jobs/${JOB_ID}/refund`,
    headers: { authorization: `Bearer ${token}` },
    payload: { reason: "Client cancelled after dispute", idempotency_key: "refund-key-0001", ...body },
  };
}

beforeEach(() => {
  getUserByCognitoSub.mockResolvedValue({
    id: ADMIN_ID,
    phone_number: "+15550000001",
    email: "admin@example.com",
    full_name: "Platform Admin",
    role: "ADMIN",
    avatar_url: null,
    is_active: true,
    is_verified: true,
    last_login_at: null,
    created_at: new Date(),
    updated_at: new Date(),
  });
});

afterEach(async () => {
  await app?.close();
  app = undefined;
  refundClientJob.mockReset();
  getUserByCognitoSub.mockReset();
  resetTestCognitoVerifier();
});

describe("POST /admin/jobs/:jobId/refund", () => {
  it("refunds a HELD escrow and drives the job to CANCELLED", async () => {
    app = await buildTestApp();
    refundClientJob.mockResolvedValue({
      auditId: "9001",
      refundLedgerTransactionId: REFUND_TXN_ID,
      refundedAmountCents: 45_000,
      currency: "INR",
      job: refundedJob("IN_PROGRESS"),
    });

    const response = await app.inject(refundRequest(adminToken()));

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.success).toBe(true);
    expect(body.data.refunded_amount_cents).toBe(45_000);
    expect(body.data.refund_ledger_transaction_id).toBe(REFUND_TXN_ID);
    // The refund is what makes cancellation reachable: escrow must land on
    // REFUNDED in the same transition, or enforce_job_financial_state rejects it.
    expect(body.data.job.status).toBe("CANCELLED");
    expect(body.data.job.escrow_status).toBe("REFUNDED");
    expect(refundClientJob).toHaveBeenCalledWith(expect.objectContaining({
      actorUserId: ADMIN_ID,
      jobId: JOB_ID,
      reason: "Client cancelled after dispute",
      idempotencyKey: "refund-key-0001",
    }));
  });

  it("refunds a FROZEN escrow, releasing a disputed job", async () => {
    app = await buildTestApp();
    refundClientJob.mockResolvedValue({
      auditId: "9002",
      refundLedgerTransactionId: REFUND_TXN_ID,
      refundedAmountCents: 45_000,
      currency: "INR",
      job: refundedJob("DISPUTED"),
    });

    const response = await app.inject(refundRequest(adminToken()));

    expect(response.statusCode).toBe(200);
    expect(response.json().data.job.status).toBe("CANCELLED");
    expect(response.json().data.job.escrow_status).toBe("REFUNDED");
  });

  it("derives a stable idempotency fingerprint from the job and key", async () => {
    app = await buildTestApp();
    refundClientJob.mockResolvedValue({
      auditId: "9003",
      refundLedgerTransactionId: REFUND_TXN_ID,
      refundedAmountCents: 45_000,
      currency: "INR",
      job: refundedJob("SUBMITTED"),
    });

    await app.inject(refundRequest(adminToken()));
    await app.inject(refundRequest(adminToken(), { reason: "A different stated reason" }));

    const [first] = refundClientJob.mock.calls[0] as [{ idempotencyFingerprint: string }];
    const [second] = refundClientJob.mock.calls[1] as [{ idempotencyFingerprint: string }];
    expect(first.idempotencyFingerprint).toMatch(/^[0-9a-f]{64}$/);
    // Same job + same key must fingerprint identically so a retry is a replay
    // rather than a 23505 conflict, even if the operator reworded the reason.
    expect(second.idempotencyFingerprint).toBe(first.idempotencyFingerprint);
  });

  it("returns 409 when the same key is replayed with different input", async () => {
    app = await buildTestApp();
    refundClientJob.mockRejectedValue(pgError("23505", "Refund idempotency key was reused with different input"));

    const response = await app.inject(refundRequest(adminToken()));

    expect(response.statusCode).toBe(409);
    expect(response.json().error.code).toBe("IDEMPOTENCY_KEY_REUSED");
  });

  it("returns 409 when the escrow is not funded", async () => {
    app = await buildTestApp();
    refundClientJob.mockRejectedValue(pgError("55000", "Only a funded escrow (HELD or FROZEN) can be refunded"));

    const response = await app.inject(refundRequest(adminToken()));

    expect(response.statusCode).toBe(409);
    expect(response.json().error.code).toBe("ADMIN_OPERATION_CONFLICT");
  });

  it("returns 409 when the job is already terminal (double refund)", async () => {
    app = await buildTestApp();
    refundClientJob.mockRejectedValue(pgError("55000", "Terminal jobs cannot be refunded"));

    const response = await app.inject(refundRequest(adminToken()));

    expect(response.statusCode).toBe(409);
    expect(response.json().error.code).toBe("ADMIN_OPERATION_CONFLICT");
  });

  it("returns 404 for an unknown job", async () => {
    app = await buildTestApp();
    refundClientJob.mockRejectedValue(pgError("P0002", "Job not found"));

    const response = await app.inject(refundRequest(adminToken()));

    expect(response.statusCode).toBe(404);
    expect(response.json().error.code).toBe("NOT_FOUND");
  });

  it("returns 403 when the caller is not an administrator", async () => {
    app = await buildTestApp();
    getUserByCognitoSub.mockResolvedValue({
      id: CLIENT_ID,
      phone_number: "+15550000002",
      email: "client@example.com",
      full_name: "Paying Client",
      role: "CLIENT",
      avatar_url: null,
      is_active: true,
      is_verified: true,
      last_login_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    });
    const token = issueTestCognitoAccessToken({ id: CLIENT_ID, phone: "+15550000002", role: "CLIENT" });

    const response = await app.inject(refundRequest(token));

    expect(response.statusCode).toBe(403);
    expect(refundClientJob).not.toHaveBeenCalled();
  });

  it("rejects an unauthenticated refund", async () => {
    app = await buildTestApp();

    const response = await app.inject({
      method: "POST",
      url: `${config.API_PREFIX}/admin/jobs/${JOB_ID}/refund`,
      payload: { reason: "No token supplied", idempotency_key: "refund-key-0001" },
    });

    expect(response.statusCode).toBe(401);
    expect(refundClientJob).not.toHaveBeenCalled();
  });

  it("rejects a missing idempotency key and a too-short reason", async () => {
    app = await buildTestApp();
    const token = adminToken();

    const missingKey = await app.inject({
      method: "POST",
      url: `${config.API_PREFIX}/admin/jobs/${JOB_ID}/refund`,
      headers: { authorization: `Bearer ${token}` },
      payload: { reason: "Client cancelled after dispute" },
    });
    const shortReason = await app.inject(refundRequest(token, { reason: "x" }));

    expect(missingKey.statusCode).toBe(400);
    expect(shortReason.statusCode).toBe(400);
    expect(refundClientJob).not.toHaveBeenCalled();
  });
});
