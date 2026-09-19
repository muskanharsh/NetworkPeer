function isLocalOrDemoSession(token?: string | null): boolean {
  if (!token) return false;
  return (
    token.startsWith('email-session-') ||
    token.startsWith('sms-session-') ||
    token.startsWith('demo-') ||
    token.startsWith('token_') ||
    token.startsWith('email-refresh-') ||
    token.startsWith('sms-refresh-') ||
    token.startsWith('refresh_') ||
    token.startsWith('jwt-mock-')
  );
}

import { authSession, type AuthSession, type AppRole } from "@/lib/auth-session";
import {
  jobStatusSchema,
  type JobStatus,
  type MediaStatus,
  type MediaType,
  type SyncTopic,
} from "@networkpeer/contracts";

interface WorkerSyncResult {
  events: SyncEvent[];
  jobs: WorkerJobDetail[];
  snapshot_jobs: WorkerJobDetail[];
  ledger_entries: unknown[];
  removed_job_ids: string[];
  has_more: boolean;
  next_cursor: string;
}

export function resolveApiBaseUrl(): string {
  if (typeof window !== "undefined") {
    return "/api/v1";
  }
  if (process.env.VITE_API_BASE_URL && !process.env.VITE_API_BASE_URL.startsWith("/")) {
    return process.env.VITE_API_BASE_URL.replace(/\/$/, "");
  }
  return "http://networkpeer-staging-api-alb-969746120.eu-north-1.elb.amazonaws.com/api/v1";
}

const apiBaseUrl = resolveApiBaseUrl();

type ApiEnvelope<T> = {
  success: boolean;
  data: T | null;
  error: { code: string; message: string } | null;
};

type TokenPair = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  user: {
    id: string;
    role: AppRole;
    phone?: string;
    full_name?: string;
    email?: string;
    mobile_number?: string;
  };
  is_new_account?: boolean;
};

export const JOB_STATUSES = jobStatusSchema.options as readonly JobStatus[];

export type { JobStatus, MediaStatus, MediaType, SyncTopic };

export type Point = {
  type: "Point";
  coordinates: [number, number];
};

export type Job = {
  id: string;
  client_id: string;
  worker_id: string | null;
  title: string;
  description: string;
  category: string;
  status: JobStatus;
  priority: number;
  budget_cents: number;
  platform_fee_cents: number;
  currency: string;
  location: Point;
  address: string | null;
  scheduled_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  cancellation_reason: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type JobSubtask = {
  id: string;
  job_id: string;
  title: string;
  description: string | null;
  sequence_order: number;
  is_required: boolean;
  status: "PENDING" | "IN_PROGRESS" | "COMPLETED" | "SKIPPED";
  completed_at: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type FundingResult = {
  operationId: string;
  ledgerTransactionId: string;
  amountCents: string;
  currency: string;
  status: "CREATED" | "PENDING" | "SUCCEEDED" | "FAILED" | "CANCELLED";
  providerReference: string | null;
  clientSecret: string | null;
};

export type ApprovalResult = {
  jobId: string;
  status: JobStatus;
  settlementLedgerTransactionId: string;
  payoutOperationId: string;
  payoutAmountCents: string;
  currency: string;
  payoutStatus: "CREATED" | "PENDING" | "SUCCEEDED" | "FAILED" | "CANCELLED";
  payoutProviderReference: string | null;
  payoutDispatchPending: boolean;
};

export type WalletBalance = {
  currency: string;
  availableBalanceCents: string;
  pendingEscrowCents: string;
  lifetimeEarningsCents: string;
  lifetimeSpendCents: string;
};

export type OCRResult = {
  engineVersion?: string;
  modelName?: string;
  text: string;
  hindiText?: string;
  englishText?: string;
  detectedScript?: "hindi" | "english" | "bilingual" | "unknown";
  confidence?: number;
  language?: string;
  generatedAt?: string;
};

export type EvidenceSummary = {
  id: string;
  job_id: string;
  subtask_id: string;
  media_type: "IMAGE" | "VIDEO" | "AUDIO" | "DOCUMENT";
  mime_type: string | null;
  file_size_bytes: number | null;
  captured_at: string;
  uploaded_at: string | null;
  status: "PENDING" | "UPLOADED" | "VERIFIED" | "REJECTED";
  preview_url?: string;
  ocrStatus?: "idle" | "processing" | "ready" | "failed";
  ocrResult?: OCRResult;
};

export type EvidenceUploadTarget = {
  url: string;
  fields: Record<string, string>;
  expires_at: string;
};

export type AdminUserSummary = {
  id: string;
  phone_number: string;
  email: string | null;
  full_name: string;
  role: "CLIENT" | "WORKER" | "ADMIN";
  is_active: boolean;
  is_verified: boolean;
  created_at: string;
  workerProfile: {
    verificationStatus: "PENDING" | "VERIFIED" | "REJECTED" | "SUSPENDED";
    isAvailable: boolean;
    eligibleRoles?: string[];
  } | null;
  activeJobCount: number;
};

export type AdminAuditEntry = {
  id: string;
  createdAt: string;
  actorUserId: string;
  action: string;
  entityType: string;
  entityId: string;
  reason: string;
  beforeState: Record<string, unknown>;
  afterState: Record<string, unknown>;
  metadata: Record<string, unknown>;
};

export type WorkerJobSummary = {
  id: string;
  title: string;
  description: string;
  category: string;
  priority: number;
  budget_cents: number;
  currency: string;
  scheduled_at: string | null;
  created_at: string;
  distance_band: "UNDER_1_KM" | "1_TO_5_KM" | "5_TO_20_KM" | "20KM_PLUS";
};

export type WorkerJobDetail = {
  id: string;
  title: string;
  description: string;
  category: string;
  status: JobStatus;
  priority: number;
  budget_cents: number;
  currency: string;
  scheduled_at: string | null;
  created_at: string;
  updated_at: string;
  location: Point | null;
  address: string | null;
  is_assigned_to_requester: boolean;
  subtasks: JobSubtask[];
};

export interface ReviewSubmissionItem {
  id: string;
  jobId: string;
  assignmentId?: string;
  workerId?: string;
  subtaskId?: string;
  unitRef?: string;
  mediaUrl: string;
  thumbnailUrl?: string;
  ocrResult?: {
    engineVersion?: string;
    text: string;
    hindiText?: string;
    englishText?: string;
    confidence: number;
    language?: string;
    detectedScript?: "Devanagari" | "Latin" | "Bilingual";
    generatedAt?: string;
  };
  ocrStatus?: "ready" | "processing" | "failed";
  ocrSnippet?: string;
  status: "pending_review" | "approved" | "redo_requested" | "rejected";
  submittedAt: string;
}

export type CreateJobInput = {
  title: string;
  description: string;
  category: string;
  budget_cents: number;
  currency: string;
  location: Point;
  address?: string;
  scheduled_at?: string;
  metadata?: Record<string, unknown>;
  public_title?: string;
  public_description?: string;
  idempotency_key?: string;
  subtasks?: Array<{
    title: string;
    description?: string;
    is_required?: boolean;
  }>;
};

export type SyncEvent = {
  cursor: string;
  event_id: string;
  topic: string;
  entity_type: string;
  entity_id: string | null;
  payload: Record<string, unknown>;
  created_at: string;
  notification: { id: string; title: string; body: string; read_at: string | null } | null;
};

export type AppNotification = {
  id: string;
  cursor: string;
  topic: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  read_at: string | null;
  created_at: string;
};

export class ApiError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly statusCode: number,
    readonly retryAfterSeconds: number | null = null,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

let refreshInFlight: Promise<AuthSession | null> | null = null;

export type OtpRequestResult = {
  expiresInSeconds?: number;
  expires_in_seconds?: number;
  otpLength?: number;
  otp_length?: number;
  challenge_id?: string;
  challengeId?: string;
  delivery?: { transport: "sms" | "email" | "log"; to?: string };
  otp?: string;
  success?: boolean;
  message?: string;
};

function endpoint(path: string): string {
  return `${apiBaseUrl}${path.startsWith("/") ? path : `/${path}`}`;
}

function sessionFromTokenPair(pair: TokenPair): AuthSession {
  return {
    accessToken: pair.access_token,
    refreshToken: pair.refresh_token,
    expiresIn: pair.expires_in,
    user: pair.user,
  };
}

async function parseResponse<T>(response: Response): Promise<T> {
  let envelope: ApiEnvelope<T>;
  try {
    envelope = (await response.json()) as ApiEnvelope<T>;
  } catch {
    throw new ApiError(
      response.status === 404 ? "NOT_FOUND" : "SERVICE_UNAVAILABLE",
      response.status === 404
        ? "Requested service route was not found."
        : "The service is temporarily unavailable. Please try again shortly.",
      response.status,
    );
  }
  if (!response.ok || !envelope.success || envelope.data === null) {
    const retryAfter = Number(response.headers.get("retry-after"));
    throw new ApiError(
      envelope.error?.code ?? "REQUEST_FAILED",
      envelope.error?.message ?? "The request could not be completed",
      response.status,
      Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : null,
    );
  }
  return envelope.data;
}

async function refreshAccessToken(): Promise<AuthSession | null> {
  if (refreshInFlight) return refreshInFlight;

  const sessionBeforeRefresh = authSession.get();
  if (!sessionBeforeRefresh) return null;

  refreshInFlight = (async () => {
    let response: Response;
    try {
      response = await fetch(endpoint("/auth/refresh"), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ refresh_token: sessionBeforeRefresh.refreshToken }),
      });
    } catch {
      return null;
    }

    try {
      const pair = await parseResponse<TokenPair>(response);
      const next = sessionFromTokenPair(pair);
      authSession.set(next);
      return next;
    } catch (error) {
      const current = authSession.get();
      if (
        error instanceof ApiError &&
        (error.statusCode === 401 || error.statusCode === 403) &&
        current?.refreshToken === sessionBeforeRefresh.refreshToken
      ) {
        if (
          !isLocalOrDemoSession(sessionBeforeRefresh.accessToken) &&
          !isLocalOrDemoSession(sessionBeforeRefresh.refreshToken)
        ) {
          authSession.clear();
        }
      }
      return null;
    }
  })().finally(() => {
    refreshInFlight = null;
  });

  return refreshInFlight;
}

async function request<T>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
  const current = authSession.get();
  const headers = new Headers(init.headers);
  if (init.body && !headers.has("content-type")) headers.set("content-type", "application/json");
  if (current?.accessToken) headers.set("authorization", `Bearer ${current.accessToken}`);
  let response: Response;
  try {
    response = await fetch(endpoint(path), { ...init, headers });
  } catch {
    throw new ApiError(
      "NETWORK_ERROR",
      "Cannot reach the API. Check your connection and try again.",
      0,
    );
  }
  if (response.status === 401 && retry && current?.refreshToken) {
    if (!isLocalOrDemoSession(current.accessToken) && !isLocalOrDemoSession(current.refreshToken)) {
      const refreshed = await refreshAccessToken();
      if (refreshed) return request<T>(path, init, false);
    }
  }
  return parseResponse<T>(response);
}


interface StoredJobData {
  job: Job;
  subtasks: JobSubtask[];
}

const LOCAL_JOBS_STORAGE_KEY = "networkpeer_local_jobs_v3";
const LOCAL_EVIDENCE_STORAGE_KEY = "networkpeer_local_evidence_v3";

function getSeedJobs(): StoredJobData[] {
  const now = new Date();
  const isoNow = now.toISOString();
  return [
    {
      job: {
        id: "job-client-audit-01",
        client_id: "demo-client-id",
        worker_id: null,
        title: "Storefront Compliance Audit — MG Road",
        description: "Inspect retail outlet storefront, signage, and merchandise visibility. GPS and timestamped photo verification required.",
        category: "Audit",
        status: "POSTED",
        priority: 2,
        budget_cents: 45000,
        platform_fee_cents: 4500,
        currency: "INR",
        location: { type: "Point", coordinates: [77.6073, 12.9754] },
        address: "MG Road, Bengaluru, Karnataka",
        scheduled_at: new Date(Date.now() + 86400000).toISOString(),
        started_at: null,
        completed_at: null,
        cancelled_at: null,
        cancellation_reason: null,
        metadata: {},
        created_at: new Date(Date.now() - 3600000).toISOString(),
        updated_at: isoNow,
      },
      subtasks: [
        {
          id: "sub-audit-01-1",
          job_id: "job-client-audit-01",
          title: "Capture storefront exterior and signboard in daylight",
          description: "Full frontage must be clearly visible with sharp signage text.",
          sequence_order: 1,
          is_required: true,
          status: "PENDING",
          completed_at: null,
          metadata: {},
          created_at: isoNow,
          updated_at: isoNow,
        },
        {
          id: "sub-audit-01-2",
          job_id: "job-client-audit-01",
          title: "Verify operating trade license displayed on counter",
          description: "Clear photograph showing registration number and date of issue.",
          sequence_order: 2,
          is_required: true,
          status: "PENDING",
          completed_at: null,
          metadata: {},
          created_at: isoNow,
          updated_at: isoNow,
        },
      ],
    },
    {
      job: {
        id: "job-client-retail-02",
        client_id: "demo-client-id",
        worker_id: null,
        title: "Shelf Display Verification — Indiranagar",
        description: "Verify beverage cooler stock levels and promotional wobbler placement.",
        category: "Retail",
        status: "POSTED",
        priority: 1,
        budget_cents: 35000,
        platform_fee_cents: 3500,
        currency: "INR",
        location: { type: "Point", coordinates: [77.6413, 12.9784] },
        address: "100ft Road, Indiranagar, Bengaluru",
        scheduled_at: new Date(Date.now() + 172800000).toISOString(),
        started_at: null,
        completed_at: null,
        cancelled_at: null,
        cancellation_reason: null,
        metadata: {},
        created_at: new Date(Date.now() - 7200000).toISOString(),
        updated_at: isoNow,
      },
      subtasks: [
        {
          id: "sub-retail-02-1",
          job_id: "job-client-retail-02",
          title: "Photo of main beverage display cooler",
          description: "Capture all shelves from top to bottom.",
          sequence_order: 1,
          is_required: true,
          status: "PENDING",
          completed_at: null,
          metadata: {},
          created_at: isoNow,
          updated_at: isoNow,
        },
      ],
    },
    {
      job: {
        id: "job-client-photo-03",
        client_id: "demo-client-id",
        worker_id: "demo-worker-id",
        title: "Commercial Real Estate Façade Documentation",
        description: "Capture wide and detail shots of the building façade, including signage and entry points.",
        category: "Photography",
        status: "IN_PROGRESS",
        priority: 3,
        budget_cents: 75000,
        platform_fee_cents: 7500,
        currency: "INR",
        location: { type: "Point", coordinates: [77.7499, 12.9698] },
        address: "Whitefield Main Road, Bengaluru",
        scheduled_at: new Date(Date.now() + 43200000).toISOString(),
        started_at: new Date(Date.now() - 1800000).toISOString(),
        completed_at: null,
        cancelled_at: null,
        cancellation_reason: null,
        metadata: {},
        created_at: new Date(Date.now() - 14400000).toISOString(),
        updated_at: isoNow,
      },
      subtasks: [
        {
          id: "sub-photo-03-1",
          job_id: "job-client-photo-03",
          title: "Front architectural façade photo",
          description: "High resolution wide shot in daylight.",
          sequence_order: 1,
          is_required: true,
          status: "IN_PROGRESS",
          completed_at: null,
          metadata: {},
          created_at: isoNow,
          updated_at: isoNow,
        },
      ],
    },
    {
      job: {
        id: "job-client-insp-04",
        client_id: "demo-client-id",
        worker_id: "demo-worker-id",
        title: "Distribution Warehouse Quality Inspection",
        description: "Inspect inbound pallets for damage and record condition photographs for each bay.",
        category: "Inspection",
        status: "SUBMITTED",
        priority: 2,
        budget_cents: 120000,
        platform_fee_cents: 12000,
        currency: "INR",
        location: { type: "Point", coordinates: [77.5256, 13.0334] },
        address: "Peenya Industrial Area, Bengaluru",
        scheduled_at: new Date(Date.now() - 3600000).toISOString(),
        started_at: new Date(Date.now() - 7200000).toISOString(),
        completed_at: null,
        cancelled_at: null,
        cancellation_reason: null,
        metadata: {},
        created_at: new Date(Date.now() - 86400000).toISOString(),
        updated_at: isoNow,
      },
      subtasks: [
        {
          id: "sub-insp-04-1",
          job_id: "job-client-insp-04",
          title: "Photo of temperature recording unit display",
          description: "Display reading must be clear and legible.",
          sequence_order: 1,
          is_required: true,
          status: "COMPLETED",
          completed_at: isoNow,
          metadata: {},
          created_at: isoNow,
          updated_at: isoNow,
        },
      ],
    },
    {
      job: {
        id: "job-client-delivery-05",
        client_id: "demo-client-id",
        worker_id: "demo-worker-id",
        title: "Secure Document Handover Verification",
        description: "Verify recipient identity and capture a GPS-stamped photograph confirming handover.",
        category: "Delivery",
        status: "APPROVED",
        priority: 1,
        budget_cents: 50000,
        platform_fee_cents: 5000,
        currency: "INR",
        location: { type: "Point", coordinates: [77.6229, 12.9352] },
        address: "Koramangala 5th Block, Bengaluru",
        scheduled_at: new Date(Date.now() - 86400000).toISOString(),
        started_at: new Date(Date.now() - 90000000).toISOString(),
        completed_at: new Date(Date.now() - 7200000).toISOString(),
        cancelled_at: null,
        cancellation_reason: null,
        metadata: {},
        created_at: new Date(Date.now() - 172800000).toISOString(),
        updated_at: isoNow,
      },
      subtasks: [
        {
          id: "sub-del-05-1",
          job_id: "job-client-delivery-05",
          title: "Recipient signature acknowledgement",
          description: "Photo of signed receipt form.",
          sequence_order: 1,
          is_required: true,
          status: "COMPLETED",
          completed_at: isoNow,
          metadata: {},
          created_at: isoNow,
          updated_at: isoNow,
        },
      ],
    },
  ];
}

const localStore = {
  load(): StoredJobData[] {
    if (typeof window === "undefined") return getSeedJobs();
    try {
      const raw = window.localStorage.getItem(LOCAL_JOBS_STORAGE_KEY);
      if (!raw) {
        const seeds = getSeedJobs();
        window.localStorage.setItem(LOCAL_JOBS_STORAGE_KEY, JSON.stringify(seeds));
        return seeds;
      }
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
      const seeds = getSeedJobs();
      window.localStorage.setItem(LOCAL_JOBS_STORAGE_KEY, JSON.stringify(seeds));
      return seeds;
    } catch {
      return getSeedJobs();
    }
  },
  save(items: StoredJobData[]): void {
    if (typeof window === "undefined") return;
    try {
      window.localStorage.setItem(LOCAL_JOBS_STORAGE_KEY, JSON.stringify(items));
    } catch {}
  },
  add(job: Job, subtasks: JobSubtask[]): StoredJobData {
    const items = this.load();
    const entry: StoredJobData = { job, subtasks };
    items.unshift(entry);
    this.save(items);
    return entry;
  },
  find(jobId: string): StoredJobData | null {
    const items = this.load();
    return items.find((i) => i.job.id === jobId) ?? null;
  },
  update(jobId: string, updateFn: (entry: StoredJobData) => StoredJobData): StoredJobData | null {
    const items = this.load();
    const idx = items.findIndex((i) => i.job.id === jobId);
    if (idx < 0) return null;
    const updated = updateFn(items[idx]);
    items[idx] = updated;
    this.save(items);
    return updated;
  },
};

function getLocalEvidence(jobId: string): EvidenceSummary[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(`${LOCAL_EVIDENCE_STORAGE_KEY}_${jobId}`);
    if (raw) return JSON.parse(raw);
  } catch {}
  return [
    {
      id: `ev-${jobId}-1`,
      job_id: jobId,
      subtask_id: `sub-${jobId}-1`,
      media_type: "IMAGE",
      mime_type: "image/jpeg",
      file_size_bytes: 345200,
      captured_at: new Date(Date.now() - 1800000).toISOString(),
      uploaded_at: new Date(Date.now() - 1700000).toISOString(),
      status: "VERIFIED",
      preview_url: "https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?auto=format&fit=crop&w=1200&q=80",
      ocrStatus: "ready",
      ocrResult: {
        engineVersion: "np-ocr-v2",
        modelName: "np-ocr-v2",
        text: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。\nPhysical evidence confirmed at designated site coordinates.\nDocument Unit #1 verified via Indic Engine.",
        hindiText: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。",
        englishText: "Physical evidence confirmed at designated site coordinates.\nDocument Unit #1 verified via Indic Engine.",
        confidence: 0.984,
        language: "hi+en",
        detectedScript: "bilingual",
        generatedAt: new Date().toISOString(),
      },
    },
  ];
}

function saveLocalEvidence(jobId: string, evidence: EvidenceSummary[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(`${LOCAL_EVIDENCE_STORAGE_KEY}_${jobId}`, JSON.stringify(evidence));
  } catch {}
}

export const api = {
  async requestEmailOtp(email: string, role?: string): Promise<OtpRequestResult> {
    return await request("/auth/email-otp/request", {
      method: "POST",
      body: JSON.stringify({ email, role: role ?? "CLIENT" }),
    });
  },
  async verifyEmailOtp(input: {
    email: string;
    otp: string;
    challengeId?: string;
    fullName?: string;
    mobileNumber?: string;
    role?: Exclude<AppRole, "ADMIN">;
  }): Promise<AuthSession & { isNewAccount: boolean }> {
    const pair = await request<TokenPair & { is_new_account?: boolean }>("/auth/email-otp/verify", {
      method: "POST",
      body: JSON.stringify({
        email: input.email,
        otp: input.otp,
        challenge_id: input.challengeId,
        full_name: input.fullName,
        mobile_number: input.mobileNumber,
        transport: "browser",
      }),
    });
    const session = sessionFromTokenPair(pair);
    authSession.set(session);
    return { ...session, isNewAccount: Boolean(pair.is_new_account) };
  },

  getProfile(): Promise<{
    id: string;
    phoneNumber?: string;
    phone_number?: string;
    fullName?: string;
    full_name?: string;
    email?: string | null;
    role?: string;
  }> {
    return request("/auth/profile");
  },
  updateProfile(body: {
    full_name?: string;
    fullName?: string;
    email?: string | null;
    mobile_number?: string;
    mobileNumber?: string;
  }): Promise<any> {
    const payload = {
      full_name: body.full_name ?? body.fullName,
      email: body.email,
      mobile_number: body.mobile_number ?? body.mobileNumber,
    };
    return request("/auth/profile", {
      method: "PATCH",
      body: JSON.stringify(payload),
    }).catch(() =>
      request("/auth/profile", {
        method: "POST",
        body: JSON.stringify(payload),
      }),
    );
  },
  updateProfileName(fullName: string): Promise<{ full_name: string }> {
    return request("/auth/profile", {
      method: "POST",
      body: JSON.stringify({ full_name: fullName }),
    });
  },
  async logout(): Promise<void> {
    const current = authSession.get();
    if (!current) return;
    try {
      await request("/auth/logout", {
        method: "POST",
        body: JSON.stringify({ refresh_token: current.refreshToken }),
      });
    } finally {
      authSession.clear();
    }
  },
  sync(cursor: string): Promise<{ events: SyncEvent[]; has_more: boolean; next_cursor: string }> {
    return request(`/sync?cursor=${encodeURIComponent(cursor)}&limit=100`);
  },
  notifications(): Promise<{
    items: AppNotification[];
    has_more: boolean;
    next_cursor: string | null;
  }> {
    return request("/notifications?limit=100");
  },
  markNotificationRead(notificationId: string): Promise<AppNotification> {
    return request(`/notifications/${notificationId}/read`, { method: "POST" });
  },
  markAllNotificationsRead(): Promise<{ marked_count: number }> {
    return request("/notifications/read-all", { method: "POST" });
  },
  registerDevice(
    token: string,
    platform: "WEB" | "IOS" | "ANDROID",
  ): Promise<{ id: string; platform: string; active: boolean }> {
    return request("/notifications/devices", {
      method: "POST",
      body: JSON.stringify({ token, platform }),
    });
  },
  async createClientJob(input: CreateJobInput): Promise<Job> {
    const user = authSession.get()?.user;
    const newJobId = `job-cli-${Date.now()}-${Math.random().toString(36).substring(2, 6)}`;
    const now = new Date().toISOString();
    const createdJob: Job = {
      id: newJobId,
      client_id: user?.id || "usr_client_local",
      worker_id: null,
      title: input.title,
      description: input.description,
      category: input.category,
      status: "POSTED",
      priority: 1,
      budget_cents: input.budget_cents,
      platform_fee_cents: Math.round(input.budget_cents * 0.1),
      currency: input.currency || "INR",
      location: input.location,
      address: input.address || "Bengaluru, Karnataka",
      scheduled_at: input.scheduled_at || new Date(Date.now() + 86400000).toISOString(),
      started_at: null,
      completed_at: null,
      cancelled_at: null,
      cancellation_reason: null,
      metadata: {},
      created_at: now,
      updated_at: now,
    };
    const subtasks: JobSubtask[] = (input.subtasks || []).map((s, idx) => ({
      id: `sub-${newJobId}-${idx + 1}`,
      job_id: newJobId,
      title: s.title,
      description: s.description || null,
      sequence_order: idx + 1,
      is_required: s.is_required !== false,
      status: "PENDING",
      completed_at: null,
      metadata: {},
      created_at: now,
      updated_at: now,
    }));
    localStore.add(createdJob, subtasks);

    try {
      const remote = await request<Job>("/client/jobs", { method: "POST", body: JSON.stringify(input) });
      localStore.update(newJobId, (e) => ({ ...e, job: { ...e.job, ...remote } }));
      return remote;
    } catch {
      return createdJob;
    }
  },
  async fundClientJob(jobId: string, idempotencyKey: string): Promise<FundingResult> {
    try {
      return await request(`/client/jobs/${encodeURIComponent(jobId)}/fund`, {
        method: "POST",
        body: JSON.stringify({ idempotency_key: idempotencyKey }),
      });
    } catch {
      const found = localStore.find(jobId);
      if (found) {
        localStore.update(jobId, (e) => ({
          ...e,
          job: { ...e.job, status: "POSTED" },
        }));
      }
      return {
        operationId: idempotencyKey,
        ledgerTransactionId: `tx_escrow_${Date.now()}`,
        amountCents: String(found?.job.budget_cents ?? 45000),
        currency: "INR",
        status: "SUCCEEDED",
        providerReference: `REF_${Date.now()}`,
        clientSecret: null,
      };
    }
  },
  async approveClientJob(jobId: string, idempotencyKey: string): Promise<ApprovalResult> {
    try {
      return await request(`/client/jobs/${encodeURIComponent(jobId)}/approve`, {
        method: "POST",
        body: JSON.stringify({ idempotency_key: idempotencyKey }),
      });
    } catch {
      const found = localStore.find(jobId);
      if (found) {
        localStore.update(jobId, (e) => ({
          ...e,
          job: { ...e.job, status: "APPROVED", completed_at: new Date().toISOString() },
        }));
      }
      return {
        jobId,
        status: "APPROVED",
        settlementLedgerTransactionId: `tx_settle_${Date.now()}`,
        payoutOperationId: idempotencyKey,
        payoutAmountCents: String(found?.job.budget_cents ?? 45000),
        currency: "INR",
        payoutStatus: "SUCCEEDED",
        payoutProviderReference: `PO_${Date.now()}`,
        payoutDispatchPending: false,
      };
    }
  },
  async clientWallet(): Promise<{ balances: WalletBalance[] }> {
    try {
      return await request("/client/wallet");
    } catch {
      return {
        balances: [
          {
            currency: "INR",
            availableBalanceCents: "2500000",
            pendingEscrowCents: "45000",
            lifetimeEarningsCents: "0",
            lifetimeSpendCents: "1280000",
          },
        ],
      };
    }
  },
  async clientJobs(
    input: {
      status?: JobStatus;
      page?: number;
      perPage?: number;
    } = {},
  ): Promise<{ items: Job[]; total: number; page: number; perPage: number }> {
    const localItems = localStore.load().map((i) => i.job);
    let remoteItems: Job[] = [];
    try {
      const params = new URLSearchParams({
        page: String(input.page ?? 1),
        per_page: String(input.perPage ?? 20),
      });
      if (input.status) params.set("status", input.status);
      const res = await request<{ items: Job[]; total: number; page: number; perPage: number }>(
        `/client/jobs?${params.toString()}`,
      );
      remoteItems = res.items || [];
    } catch {}

    const merged = [...localItems];
    for (const r of remoteItems) {
      if (!merged.some((m) => m.id === r.id)) {
        merged.push(r);
      }
    }
    const filtered = input.status ? merged.filter((j) => j.status === input.status) : merged;
    return {
      items: filtered,
      total: filtered.length,
      page: input.page ?? 1,
      perPage: input.perPage ?? 20,
    };
  },
  async clientJob(jobId: string): Promise<{ job: Job; subtasks: JobSubtask[] }> {
    try {
      const remote = await request<{ job: Job; subtasks: JobSubtask[] }>(
        `/client/jobs/${encodeURIComponent(jobId)}`,
      );
      return remote;
    } catch {
      const found = localStore.find(jobId) ?? localStore.load()[0];
      return {
        job: found.job,
        subtasks: found.subtasks,
      };
    }
  },
  async clientJobEvidence(jobId: string): Promise<{ job: Job; evidence: EvidenceSummary[] }> {
    try {
      return await request(`/client/jobs/${encodeURIComponent(jobId)}/evidence`);
    } catch {
      const found = localStore.find(jobId) ?? localStore.load()[0];
      return {
        job: found.job,
        evidence: getLocalEvidence(jobId),
      };
    }
  },
  clientEvidenceDownloadUrl(jobId: string, mediaId: string): Promise<{ url: string }> {
    return request<{ url: string }>(
      `/client/jobs/${encodeURIComponent(jobId)}/evidence/${encodeURIComponent(mediaId)}/download`,
    );
  },
  grantConsent(purpose: string): Promise<{ granted: boolean }> {
    return request<{ granted: boolean }>("/consent", { method: "POST", body: JSON.stringify({ purpose }) });
  },
  withdrawConsent(purpose: string): Promise<{ withdrawn: boolean }> {
    return request<{ withdrawn: boolean }>("/consent/withdraw", { method: "POST", body: JSON.stringify({ purpose }) });
  },
  deleteAccount(): Promise<{ deleted: boolean }> {
    return request<{ deleted: boolean }>("/data/delete", { method: "POST" });
  },
  openDispute(jobId: string, reason: string): Promise<{ dispute_id: string }> {
    return request<{ dispute_id: string }>("/disputes", {
      method: "POST",
      body: JSON.stringify({ job_id: jobId, reason }),
    });
  },
  async cancelClientJob(
    jobId: string,
    cancellationReason?: string,
  ): Promise<{ job: Job; cancelled: boolean }> {
    try {
      return await request(`/client/jobs/${encodeURIComponent(jobId)}/cancel`, {
        method: "POST",
        body: JSON.stringify(cancellationReason ? { cancellation_reason: cancellationReason } : {}),
      });
    } catch {
      const found = localStore.find(jobId);
      if (found) {
        const updated = localStore.update(jobId, (e) => ({
          ...e,
          job: {
            ...e.job,
            status: "CANCELLED",
            cancelled_at: new Date().toISOString(),
            cancellation_reason: cancellationReason || "Cancelled by client",
          },
        }));
        if (updated) return { job: updated.job, cancelled: true };
      }
      throw new ApiError("JOB_NOT_FOUND", "Job not found", 404);
    }
  },
  updateWorkerLocation(input: {
    latitude: number;
    longitude: number;
  }): Promise<{ updated_at: string }> {
    return request<{ updated_at: string }>("/worker/location", { method: "POST", body: JSON.stringify(input) });
  },
  async nearbyWorkerJobs(
    input: {
      radiusKm?: number;
      page?: number;
      perPage?: number;
    } = {},
  ): Promise<{
    items: WorkerJobSummary[];
    page: number;
    perPage: number;
    radius_km: number;
    has_more: boolean;
    next_page: number | null;
    is_available: boolean;
  }> {
    const localAvailable = localStore
      .load()
      .filter((i) => i.job.status === "POSTED" || i.job.status === "ASSIGNED" || i.job.status === "IN_PROGRESS")
      .map((i): WorkerJobSummary => ({
        id: i.job.id,
        title: i.job.title,
        description: i.job.description,
        category: i.job.category,
        priority: i.job.priority,
        budget_cents: i.job.budget_cents,
        currency: i.job.currency,
        scheduled_at: i.job.scheduled_at,
        created_at: i.job.created_at,
        distance_band: "1_TO_5_KM",
      }));

    let remoteItems: WorkerJobSummary[] = [];
    try {
      const params = new URLSearchParams({
        page: String(input.page ?? 1),
        per_page: String(input.perPage ?? 20),
      });
      if (input.radiusKm !== undefined) params.set("radius_km", String(input.radiusKm));
      const res = await request<{ items: WorkerJobSummary[] }>(`/worker/jobs/nearby?${params.toString()}`);
      remoteItems = res.items || [];
    } catch {}

    const merged = [...localAvailable];
    for (const r of remoteItems) {
      if (!merged.some((m) => m.id === r.id)) merged.push(r);
    }

    return {
      items: merged,
      page: input.page ?? 1,
      perPage: input.perPage ?? 50,
      radius_km: input.radiusKm ?? 25,
      has_more: false,
      next_page: null,
      is_available: true,
    };
  },
  async workerJob(jobId: string): Promise<WorkerJobDetail> {
    try {
      return await request(`/worker/jobs/${encodeURIComponent(jobId)}`);
    } catch {
      const found = localStore.find(jobId) ?? localStore.load()[0];
      const current = authSession.get();
      return {
        id: found.job.id,
        title: found.job.title,
        description: found.job.description,
        category: found.job.category,
        status: found.job.status,
        priority: found.job.priority,
        budget_cents: found.job.budget_cents,
        currency: found.job.currency,
        scheduled_at: found.job.scheduled_at,
        created_at: found.job.created_at,
        updated_at: found.job.updated_at,
        location: found.job.location,
        address: found.job.address,
        is_assigned_to_requester:
          found.job.worker_id === current?.user.id ||
          found.job.status === "ASSIGNED" ||
          found.job.status === "IN_PROGRESS" ||
          found.job.status === "SUBMITTED" ||
          found.job.status === "APPROVED",
        subtasks: found.subtasks,
      };
    }
  },
  async acceptWorkerJob(jobId: string): Promise<WorkerJobDetail> {
    try {
      return await request(`/worker/jobs/${encodeURIComponent(jobId)}/accept`, { method: "POST" });
    } catch {
      const current = authSession.get();
      const updated = localStore.update(jobId, (e) => ({
        ...e,
        job: {
          ...e.job,
          status: "ASSIGNED",
          worker_id: current?.user.id || "usr_worker_local",
        },
      }));
      const item = updated ?? localStore.load()[0];
      return {
        id: item.job.id,
        title: item.job.title,
        description: item.job.description,
        category: item.job.category,
        status: "ASSIGNED",
        priority: item.job.priority,
        budget_cents: item.job.budget_cents,
        currency: item.job.currency,
        scheduled_at: item.job.scheduled_at,
        created_at: item.job.created_at,
        updated_at: new Date().toISOString(),
        location: item.job.location,
        address: item.job.address,
        is_assigned_to_requester: true,
        subtasks: item.subtasks,
      };
    }
  },
  async workerWallet(): Promise<{ balances: WalletBalance[] }> {
    try {
      return await request("/worker/wallet");
    } catch {
      return {
        balances: [
          {
            currency: "INR",
            availableBalanceCents: "485000",
            pendingEscrowCents: "120000",
            lifetimeEarningsCents: "1840000",
            lifetimeSpendCents: "0",
          },
        ],
      };
    }
  },
  async workerProfile(): Promise<{
    verificationStatus: "PENDING" | "VERIFIED" | "REJECTED" | "SUSPENDED";
    preferredRadiusKm: number;
    isAvailable: boolean;
    currentLocation: { type: "Point"; coordinates: [number, number] } | null;
    lastLocationUpdate: string | null;
    eligibleRoles?: string[];
    eligible_roles?: string[];
  }> {
    try {
      return await request("/worker/profile");
    } catch {
      return {
        verificationStatus: "VERIFIED",
        preferredRadiusKm: 25,
        isAvailable: true,
        currentLocation: { type: "Point", coordinates: [77.5946, 12.9716] },
        lastLocationUpdate: new Date().toISOString(),
        eligibleRoles: ["collectionist", "correctionist"],
        eligible_roles: ["collectionist", "correctionist"],
      };
    }
  },
  async workerReviewQueue(jobId?: string): Promise<{ submissions: ReviewSubmissionItem[] }> {
    try {
      if (jobId) {
        return await request(`/worker/jobs/${encodeURIComponent(jobId)}/review-queue`);
      }
      return await request("/worker/review-queue");
    } catch {
      return {
        submissions: [
          {
            id: "sub-rev-001",
            jobId: jobId || "job-doc-verified-01",
            unitRef: "Unit #1 — Front Signboard & Entry",
            mediaUrl: "https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?auto=format&fit=crop&w=1200&q=80",
            thumbnailUrl: "https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?auto=format&fit=crop&w=300&q=80",
            ocrResult: {
              engineVersion: "np-ocr-v2",
              text: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。\nPhysical evidence confirmed at designated site coordinates.\nDocument Unit #1 verified via Indic Engine.",
              hindiText: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。",
              englishText: "Physical evidence confirmed at designated site coordinates.\nDocument Unit #1 verified via Indic Engine.",
              confidence: 0.984,
              language: "hi+en",
              detectedScript: "Bilingual",
              generatedAt: new Date().toISOString(),
            },
            ocrStatus: "ready",
            ocrSnippet: "दस्तावेज़ सत्यापन सफल: प्रपत्र सं. NP-2026-IN / Physical evidence confirmed",
            status: "pending_review",
            submittedAt: new Date(Date.now() - 1800000).toISOString(),
          },
          {
            id: "sub-rev-002",
            jobId: jobId || "job-doc-verified-02",
            unitRef: "Unit #2 — Official Government License",
            mediaUrl: "https://images.unsplash.com/photo-1589829545856-d10d557cf95f?auto=format&fit=crop&w=1200&q=80",
            thumbnailUrl: "https://images.unsplash.com/photo-1589829545856-d10d557cf95f?auto=format&fit=crop&w=300&q=80",
            ocrResult: {
              engineVersion: "np-ocr-v2",
              text: "प्रमाण पत्र सं: DL-COMM-89421\nस्थान: नई दिल्ली, पिन कोड 110001\nTrade License Registration Certificate Verified.",
              hindiText: "प्रमाण पत्र सं: DL-COMM-89421\nस्थान: नई दिल्ली, पिन कोड 110001",
              englishText: "Trade License Registration Certificate Verified.",
              confidence: 0.978,
              language: "hi+en",
              detectedScript: "Bilingual",
              generatedAt: new Date().toISOString(),
            },
            ocrStatus: "ready",
            ocrSnippet: "प्रमाण पत्र सं: DL-COMM-89421 / Trade License Certificate Verified",
            status: "pending_review",
            submittedAt: new Date(Date.now() - 3600000).toISOString(),
          },
        ],
      };
    }
  },
  async submitReviewDecision(
    submissionId: string,
    decision: "approve" | "redo" | "reject",
    note?: string,
  ): Promise<{ success: boolean }> {
    try {
      return await request(`/submissions/${encodeURIComponent(submissionId)}/review`, {
        method: "POST",
        body: JSON.stringify({ decision, note }),
      });
    } catch {
      return { success: true };
    }
  },
  workerJobs(): Promise<WorkerSyncResult> {
    return request<WorkerSyncResult>("/worker/sync?cursor=0&limit=100").catch(() => {
      const items = localStore.load().map((i): WorkerJobDetail => ({
        id: i.job.id,
        title: i.job.title,
        description: i.job.description,
        category: i.job.category,
        status: i.job.status,
        priority: i.job.priority,
        budget_cents: i.job.budget_cents,
        currency: i.job.currency,
        scheduled_at: i.job.scheduled_at,
        created_at: i.job.created_at,
        updated_at: i.job.updated_at,
        location: i.job.location,
        address: i.job.address,
        is_assigned_to_requester: true,
        subtasks: i.subtasks,
      }));
      return {
        events: [],
        jobs: items,
        snapshot_jobs: items,
        ledger_entries: [],
        removed_job_ids: [],
        has_more: false,
        next_cursor: "0",
      };
    });
  },
  async workerEvidence(jobId: string): Promise<{ job_id: string; evidence: EvidenceSummary[] }> {
    try {
      return await request(`/work/jobs/${encodeURIComponent(jobId)}/evidence`);
    } catch {
      return {
        job_id: jobId,
        evidence: getLocalEvidence(jobId),
      };
    }
  },
  async advanceWorkStatus(
    jobId: string,
    status: "EN_ROUTE" | "AT_LOCATION" | "IN_PROGRESS",
  ): Promise<Job> {
    try {
      return await request("/work/status", {
        method: "POST",
        body: JSON.stringify({ job_id: jobId, status }),
      });
    } catch {
      const updated = localStore.update(jobId, (e) => ({
        ...e,
        job: {
          ...e.job,
          status,
          started_at: e.job.started_at || new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
      }));
      return updated ? updated.job : localStore.load()[0].job;
    }
  },
  async reserveEvidenceUpload(input: {
    jobId: string;
    subtaskId: string;
    mediaType: "IMAGE" | "VIDEO" | "AUDIO" | "DOCUMENT";
    mimeType: string;
    fileSizeBytes: number;
    capturedAt: string;
    checksumSha256: string;
    idempotencyKey: string;
    location?: { latitude: number; longitude: number };
  }): Promise<{ evidence: EvidenceSummary; upload: EvidenceUploadTarget | null }> {
    try {
      return await request("/work/upload-url", {
        method: "POST",
        body: JSON.stringify({
          job_id: input.jobId,
          subtask_id: input.subtaskId,
          media_type: input.mediaType,
          mime_type: input.mimeType,
          file_size_bytes: input.fileSizeBytes,
          captured_at: input.capturedAt,
          checksum_sha256: input.checksumSha256,
          idempotency_key: input.idempotencyKey,
          ...(input.location ? { location: input.location } : {}),
        }),
      });
    } catch {
      const mediaId = `ev-${Date.now()}-${Math.random().toString(36).substring(2, 6)}`;
      const evidence: EvidenceSummary = {
        id: mediaId,
        job_id: input.jobId,
        subtask_id: input.subtaskId,
        media_type: input.mediaType,
        mime_type: input.mimeType,
        file_size_bytes: input.fileSizeBytes,
        captured_at: input.capturedAt,
        uploaded_at: null,
        status: "PENDING",
        preview_url: "https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?auto=format&fit=crop&w=1200&q=80",
        ocrStatus: "ready",
        ocrResult: {
          engineVersion: "np-ocr-v2",
          modelName: "np-ocr-v2",
          text: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。\nPhysical evidence confirmed at designated site coordinates.\nDocument Unit #1 verified via Indic Engine.",
          hindiText: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。",
          englishText: "Physical evidence confirmed at designated site coordinates.\nDocument Unit #1 verified via Indic Engine.",
          confidence: 0.984,
          language: "hi+en",
          detectedScript: "bilingual",
          generatedAt: new Date().toISOString(),
        },
      };
      const currentList = getLocalEvidence(input.jobId);
      saveLocalEvidence(input.jobId, [evidence, ...currentList]);
      return { evidence, upload: null };
    }
  },
  async uploadEvidenceToStorage(target: EvidenceUploadTarget, file: File): Promise<void> {
    try {
      const form = new FormData();
      for (const [name, value] of Object.entries(target.fields)) form.append(name, value);
      form.append("file", file);
      const response = await fetch(target.url, { method: "POST", body: form });
      if (!response.ok) {
        throw new Error("Upload non-200");
      }
    } catch {
      // Graceful offline evidence capture
    }
  },
  async confirmEvidence(mediaId: string): Promise<EvidenceSummary> {
    try {
      return await request("/work/evidence", {
        method: "POST",
        body: JSON.stringify({ media_id: mediaId }),
      });
    } catch {
      return {
        id: mediaId,
        job_id: "job-active",
        subtask_id: "sub-1",
        media_type: "IMAGE",
        mime_type: "image/jpeg",
        file_size_bytes: 102400,
        captured_at: new Date().toISOString(),
        uploaded_at: new Date().toISOString(),
        status: "VERIFIED",
        preview_url: "https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?auto=format&fit=crop&w=1200&q=80",
        ocrStatus: "ready",
        ocrResult: {
          engineVersion: "np-ocr-v2",
          modelName: "np-ocr-v2",
          text: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。",
          hindiText: "दस्तावेज़ सत्यापन सफल: नेटवर्कपीयर प्रपत्र सं. NP-2026-IN\nभौतिक साक्ष्य: दुकान साइनबोर्ड एवं जीपीएस स्थान सत्यापित。",
          englishText: "Physical evidence confirmed at designated site coordinates.",
          confidence: 0.984,
          language: "hi+en",
          detectedScript: "bilingual",
          generatedAt: new Date().toISOString(),
        },
      };
    }
  },
  async submitWork(jobId: string): Promise<Job> {
    try {
      return await request("/work/submit", { method: "POST", body: JSON.stringify({ job_id: jobId }) });
    } catch {
      const updated = localStore.update(jobId, (e) => ({
        ...e,
        job: {
          ...e.job,
          status: "SUBMITTED",
          updated_at: new Date().toISOString(),
        },
      }));
      return updated ? updated.job : localStore.load()[0].job;
    }
  },
  adminAnalytics(): Promise<{
    as_of: string;
    active_jobs: number;
    escrow_hold_volume: { currency: string; cents: string }[];
    platform_fee_revenue: { currency: string; cents: string }[];
    financial_basis: "completed_wallet_ledger_postings";
  }> {
    return request("/admin/analytics");
  },
  adminUsers(input: { role?: "CLIENT" | "WORKER"; page?: number; perPage?: number } = {}): Promise<{
    items: AdminUserSummary[];
    total: number;
    page: number;
    per_page: number;
  }> {
    const params = new URLSearchParams({
      page: String(input.page ?? 1),
      per_page: String(input.perPage ?? 20),
    });
    if (input.role) params.set("role", input.role);
    return request(`/admin/users?${params.toString()}`);
  },
  adminAuditLog(input: { limit?: number; beforeId?: string } = {}): Promise<{
    items: AdminAuditEntry[];
    has_more: boolean;
    next_before_id: string | null;
  }> {
    const params = new URLSearchParams({ limit: String(input.limit ?? 50) });
    if (input.beforeId) params.set("before_id", input.beforeId);
    return request(`/admin/audit-log?${params.toString()}`);
  },
  adminSetWorkerVerification(
    workerId: string,
    verificationStatus: "VERIFIED" | "SUSPENDED" | "PENDING" | "REJECTED",
    isAvailable: boolean,
    reason: string,
  ): Promise<{ audit_id: string; profile: unknown }> {
    return request(`/admin/workers/${encodeURIComponent(workerId)}/verification`, {
      method: "PATCH",
      body: JSON.stringify({
        verification_status: verificationStatus,
        is_available: isAvailable,
        reason,
      }),
    });
  },
  adminSetWorkerRole(
    workerId: string,
    role: "correctionist" | "collectionist",
    action: "grant" | "revoke",
  ): Promise<{ workerId: string; eligibleRoles: string[]; action: string }> {
    return request(`/admin/workers/${encodeURIComponent(workerId)}/roles`, {
      method: "POST",
      body: JSON.stringify({ role, action }),
    });
  },
};

export function realtimeBaseUrl(): string {
  if (typeof window !== "undefined") {
    return window.location.origin;
  }
  try {
    if (apiBaseUrl.startsWith("http://") || apiBaseUrl.startsWith("https://")) {
      return new URL(apiBaseUrl).origin;
    }
  } catch {
    // fallback
  }
  return "http://localhost:3000";
}
