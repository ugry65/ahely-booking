import {
  buildOutboundBookingEmail,
  classifyEmailTransportError,
  type BookingEmailSenderConfig,
  type EmailTransport,
} from "./provider";
import {
  parseBookingEmailJob,
  type BookingEmailEventType,
  type BookingEmailScope,
} from "./schema";

export const BOOKING_EMAIL_MODES = ["disabled", "capture", "send"] as const;
export type BookingEmailMode = (typeof BOOKING_EMAIL_MODES)[number];

export type ClaimedBookingEmail = {
  id: string;
  leaseToken: string;
  eventType: BookingEmailEventType;
  scope: BookingEmailScope;
  recipientEmail: string;
  payloadVersion: number;
  payload: unknown;
  attempts: number;
};

export type BookingEmailCompletion = {
  outboxId: string;
  leaseToken: string;
  result: "sent" | "captured" | "retry" | "dead_letter";
  providerMessageId?: string;
  errorCode?: string;
  errorSafe?: string;
  durationMs: number;
  nextAttemptAt?: string;
};

export interface BookingEmailOutboxStore {
  claim(batchSize: number, leaseSeconds: number): Promise<ClaimedBookingEmail[]>;
  complete(completion: BookingEmailCompletion): Promise<void>;
}

export type BookingEmailWorkerSummary = {
  mode: BookingEmailMode;
  claimed: number;
  sent: number;
  captured: number;
  retry: number;
  deadLetter: number;
};

export type BookingEmailWorkerOptions = {
  mode: Exclude<BookingEmailMode, "disabled">;
  store: BookingEmailOutboxStore;
  transport: EmailTransport;
  senderConfig: BookingEmailSenderConfig;
  batchSize?: number;
  leaseSeconds?: number;
  now?: () => Date;
};

const RETRY_DELAYS_MINUTES = [1, 5, 15, 60, 240, 720, 1440] as const;
const MAX_ATTEMPTS = 8;

function elapsedMilliseconds(startedAt: number): number {
  return Math.max(0, Math.min(2_147_483_647, Math.round(Date.now() - startedAt)));
}

function nextAttemptAt(now: Date, attemptsBeforeClaim: number): string | undefined {
  const delay = RETRY_DELAYS_MINUTES[attemptsBeforeClaim];
  if (delay === undefined) return undefined;
  return new Date(now.getTime() + delay * 60_000).toISOString();
}

export async function processBookingEmailBatch(
  options: BookingEmailWorkerOptions,
): Promise<BookingEmailWorkerSummary> {
  const batchSize = options.batchSize ?? 10;
  const leaseSeconds = options.leaseSeconds ?? 300;
  const jobs = await options.store.claim(batchSize, leaseSeconds);
  const summary: BookingEmailWorkerSummary = {
    mode: options.mode,
    claimed: jobs.length,
    sent: 0,
    captured: 0,
    retry: 0,
    deadLetter: 0,
  };

  for (const job of jobs) {
    const startedAt = Date.now();
    let message;

    try {
      const parsedPayload = parseBookingEmailJob({
        id: job.id,
        eventType: job.eventType,
        recipientEmail: job.recipientEmail,
        payloadVersion: job.payloadVersion,
        payload: job.payload,
      });
      if (parsedPayload.scope !== job.scope) {
        throw new Error("Az outbox scope és a payload scope eltér.");
      }
      message = buildOutboundBookingEmail({
        id: job.id,
        eventType: job.eventType,
        recipientEmail: job.recipientEmail,
        payloadVersion: job.payloadVersion,
        payload: job.payload,
      }, options.senderConfig);
    } catch {
      await options.store.complete({
        outboxId: job.id,
        leaseToken: job.leaseToken,
        result: "dead_letter",
        errorCode: "payload_invalid",
        errorSafe: "A booking e-mail adatszerkezete nem támogatott.",
        durationMs: elapsedMilliseconds(startedAt),
      });
      summary.deadLetter += 1;
      continue;
    }

    let delivery;
    try {
      delivery = await options.transport.send(message);
    } catch (error) {
      const classified = classifyEmailTransportError(error);
      const retryAt = classified.disposition === "retry" && job.attempts + 1 < MAX_ATTEMPTS
        ? nextAttemptAt(options.now?.() ?? new Date(), job.attempts)
        : undefined;
      const result = retryAt ? "retry" : "dead_letter";
      await options.store.complete({
        outboxId: job.id,
        leaseToken: job.leaseToken,
        result,
        errorCode: retryAt ? classified.code : classified.disposition === "retry" ? "smtp_retry_exhausted" : classified.code,
        errorSafe: retryAt ? classified.safeMessage : classified.disposition === "retry"
          ? "Az e-mail elérte a maximális próbálkozásszámot."
          : classified.safeMessage,
        durationMs: elapsedMilliseconds(startedAt),
        nextAttemptAt: retryAt,
      });
      summary[result === "retry" ? "retry" : "deadLetter"] += 1;
      continue;
    }

    await options.store.complete({
      outboxId: job.id,
      leaseToken: job.leaseToken,
      result: delivery.outcome,
      providerMessageId: delivery.outcome === "sent" ? delivery.providerMessageId : undefined,
      durationMs: elapsedMilliseconds(startedAt),
    });
    summary[delivery.outcome] += 1;
  }

  return summary;
}

export function disabledBookingEmailWorkerSummary(): BookingEmailWorkerSummary {
  return { mode: "disabled", claimed: 0, sent: 0, captured: 0, retry: 0, deadLetter: 0 };
}
