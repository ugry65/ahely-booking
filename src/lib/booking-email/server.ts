import "server-only";

import nodemailer from "nodemailer";

import { requireEnv } from "@/lib/env";
import { createAdminClient } from "@/lib/supabase/admin";

import {
  createCaptureTransport,
  createNodemailerCompatibleTransport,
  validateBookingEmailSenderConfig,
  type BookingEmailSenderConfig,
  type EmailTransport,
} from "./provider";
import type { BookingEmailEventType, BookingEmailScope } from "./schema";
import {
  BOOKING_EMAIL_MODES,
  runAuditedBookingEmailBatch,
  type BookingEmailCompletion,
  type BookingEmailMode,
  type BookingEmailOutboxStore,
  type BookingEmailWorkerRunCompletion,
  type BookingEmailWorkerRunStore,
  type ClaimedBookingEmail,
} from "./worker";
import type { BookingEmailWorkerRuntime } from "./worker-route";

type RpcResult = { data: unknown; error: { message?: string } | null };

function readMode(): BookingEmailMode {
  const value = process.env.BOOKING_EMAIL_MODE?.trim() || "disabled";
  if (!BOOKING_EMAIL_MODES.includes(value as BookingEmailMode)) {
    throw new Error("Érvénytelen BOOKING_EMAIL_MODE.");
  }
  return value as BookingEmailMode;
}

function positiveInteger(name: string, fallback: number, min: number, max: number): number {
  const raw = process.env[name]?.trim();
  if (!raw) return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`Érvénytelen ${name}.`);
  }
  return parsed;
}

function booleanEnv(name: string): boolean {
  const value = requireEnv(name).trim().toLowerCase();
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`Érvénytelen ${name}.`);
}

function senderConfig(): BookingEmailSenderConfig {
  return validateBookingEmailSenderConfig({
    from: requireEnv("BOOKING_EMAIL_FROM"),
    replyTo: requireEnv("BOOKING_EMAIL_REPLY_TO"),
    messageIdDomain: process.env.BOOKING_EMAIL_MESSAGE_ID_DOMAIN?.trim() || "a-hely.com",
  });
}

function claimedRows(value: unknown): ClaimedBookingEmail[] {
  if (!Array.isArray(value)) throw new Error("Érvénytelen outbox claim válasz.");
  return value.map((entry) => {
    if (!entry || typeof entry !== "object") throw new Error("Érvénytelen outbox claim sor.");
    const row = entry as Record<string, unknown>;
    if (
      typeof row.id !== "string"
      || typeof row.lease_token !== "string"
      || typeof row.event_type !== "string"
      || typeof row.scope !== "string"
      || typeof row.recipient_email !== "string"
      || typeof row.payload_version !== "number"
      || typeof row.attempts !== "number"
    ) {
      throw new Error("Hiányos outbox claim sor.");
    }
    return {
      id: row.id,
      leaseToken: row.lease_token,
      eventType: row.event_type as BookingEmailEventType,
      scope: row.scope as BookingEmailScope,
      recipientEmail: row.recipient_email,
      payloadVersion: row.payload_version,
      payload: row.payload,
      attempts: row.attempts,
    };
  });
}

async function rpcResult(result: PromiseLike<RpcResult>): Promise<unknown> {
  const { data, error } = await result;
  if (error) throw new Error("A booking e-mail outbox RPC sikertelen.");
  return data;
}

type BookingEmailWorkerStore = BookingEmailOutboxStore & BookingEmailWorkerRunStore;

function workerRunId(value: unknown): string {
  if (typeof value !== "string" || !value) throw new Error("Érvénytelen worker-futás azonosító.");
  return value;
}

function createStore(): BookingEmailWorkerStore {
  const admin = createAdminClient();
  return {
    async claim(batchSize, leaseSeconds) {
      const data = await rpcResult(admin.rpc("claim_booking_email_outbox", {
        p_batch_size: batchSize,
        p_lease_seconds: leaseSeconds,
      }));
      return claimedRows(data);
    },
    async complete(completion: BookingEmailCompletion) {
      await rpcResult(admin.rpc("complete_booking_email_outbox", {
        p_outbox_id: completion.outboxId,
        p_lease_token: completion.leaseToken,
        p_result: completion.result,
        p_provider_message_id: completion.providerMessageId ?? null,
        p_error_code: completion.errorCode ?? null,
        p_error_safe: completion.errorSafe ?? null,
        p_duration_ms: completion.durationMs,
        p_next_attempt_at: completion.nextAttemptAt ?? null,
      }));
    },
    async start(mode) {
      return workerRunId(await rpcResult(admin.rpc("start_booking_email_worker_run", {
        p_mode: mode,
      })));
    },
    async finish(runId, completion: BookingEmailWorkerRunCompletion) {
      const summary = completion.outcome === "success" ? completion.summary : null;
      await rpcResult(admin.rpc("finish_booking_email_worker_run", {
        p_run_id: runId,
        p_outcome: completion.outcome,
        p_claimed_count: summary?.claimed ?? 0,
        p_sent_count: summary?.sent ?? 0,
        p_captured_count: summary?.captured ?? 0,
        p_retry_count: summary?.retry ?? 0,
        p_dead_letter_count: summary?.deadLetter ?? 0,
        p_error_code: completion.outcome === "failed" ? completion.errorCode : null,
        p_error_safe: completion.outcome === "failed" ? completion.errorSafe : null,
      }));
    },
  };
}

function createSmtpTransport(): EmailTransport {
  const port = positiveInteger("SMTP_PORT", 465, 1, 65_535);
  const client = nodemailer.createTransport({
    host: requireEnv("SMTP_HOST"),
    port,
    secure: booleanEnv("SMTP_SECURE"),
    auth: {
      user: requireEnv("SMTP_USER"),
      pass: requireEnv("SMTP_PASS"),
    },
    connectionTimeout: 15_000,
    greetingTimeout: 15_000,
    socketTimeout: 30_000,
    disableFileAccess: true,
    disableUrlAccess: true,
    logger: false,
    debug: false,
  });
  return createNodemailerCompatibleTransport(client);
}

export function getBookingEmailCronSecret(): string {
  const secret = requireEnv("CRON_SECRET");
  if (Buffer.byteLength(secret, "utf8") < 32 || /[\r\n]/.test(secret)) {
    throw new Error("A CRON_SECRET legalább 32 bájtos, egysoros titok legyen.");
  }
  return secret;
}

export function createBookingEmailWorkerRuntime(): BookingEmailWorkerRuntime {
  const mode = readMode();
  if (mode === "disabled") return { mode };

  const config = senderConfig();
  const transport = mode === "capture" ? createCaptureTransport() : createSmtpTransport();
  const batchSize = positiveInteger("BOOKING_EMAIL_BATCH_SIZE", 10, 1, 100);
  const leaseSeconds = positiveInteger("BOOKING_EMAIL_LEASE_SECONDS", 300, 30, 900);
  const store = createStore();

  return {
    mode,
    run: () => runAuditedBookingEmailBatch({
      mode,
      store,
      runStore: store,
      transport,
      senderConfig: config,
      batchSize,
      leaseSeconds,
    }),
  };
}
