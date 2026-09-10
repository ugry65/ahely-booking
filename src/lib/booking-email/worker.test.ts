import { describe, expect, it, vi } from "vitest";

import { createCaptureTransport, type EmailTransport } from "./provider";
import {
  processBookingEmailBatch,
  runAuditedBookingEmailBatch,
  type BookingEmailCompletion,
  type BookingEmailOutboxStore,
  type BookingEmailWorkerRunStore,
  type ClaimedBookingEmail,
} from "./worker";

const payload = {
  recipient_name: "Minta Mária",
  room_name: "1.Szoba-családi",
  start_at: "2026-10-05T07:00:00Z",
  end_at: "2026-10-05T08:00:00Z",
  use_type: "individual",
  scope: "single",
  affected_count: 1,
  first_start_at: "2026-10-05T07:00:00Z",
  last_end_at: "2026-10-05T08:00:00Z",
  performed_by_admin: false,
};

const job: ClaimedBookingEmail = {
  id: "a5000000-0000-0000-0000-000000000201",
  leaseToken: "b5000000-0000-0000-0000-000000000201",
  eventType: "booking.created",
  scope: "single",
  recipientEmail: "maria@example.com",
  payloadVersion: 1,
  payload,
  attempts: 0,
};

const senderConfig = {
  from: "A-Hely Foglalás <foglalas@a-hely.com>",
  replyTo: "foglalas@a-hely.com",
  messageIdDomain: "a-hely.com",
};

function storeFor(
  jobs: ClaimedBookingEmail[],
  complete = vi.fn<(completion: BookingEmailCompletion) => Promise<void>>().mockResolvedValue(undefined),
): BookingEmailOutboxStore & { complete: typeof complete; claim: ReturnType<typeof vi.fn> } {
  const claim = vi.fn().mockResolvedValue(jobs);
  return { claim, complete };
}

describe("booking e-mail worker", () => {
  it("üres batch esetén nem végez completiont", async () => {
    const store = storeFor([]);
    const summary = await processBookingEmailBatch({
      mode: "capture", store, transport: createCaptureTransport(), senderConfig,
    });
    expect(summary).toEqual({ mode: "capture", claimed: 0, sent: 0, captured: 0, retry: 0, deadLetter: 0 });
    expect(store.claim).toHaveBeenCalledWith(10, 300);
    expect(store.complete).not.toHaveBeenCalled();
  });

  it("a sikeres üres futást is heartbeatként és pontos összesítővel naplózza", async () => {
    const store = storeFor([]);
    const runStore: BookingEmailWorkerRunStore = {
      start: vi.fn().mockResolvedValue("run-201"),
      finish: vi.fn().mockResolvedValue(undefined),
    };
    const summary = await runAuditedBookingEmailBatch({
      mode: "capture",
      store,
      runStore,
      transport: createCaptureTransport(),
      senderConfig,
    });
    expect(runStore.start).toHaveBeenCalledWith("capture");
    expect(runStore.finish).toHaveBeenCalledWith("run-201", { outcome: "success", summary });
  });

  it("a worker-hibát nyers hiba nélkül failed futásként naplózza", async () => {
    const store = storeFor([]);
    store.claim.mockRejectedValue(new Error("SUPABASE_SERVICE_ROLE_KEY=private"));
    const runStore: BookingEmailWorkerRunStore = {
      start: vi.fn().mockResolvedValue("run-202"),
      finish: vi.fn().mockResolvedValue(undefined),
    };
    await expect(runAuditedBookingEmailBatch({
      mode: "send",
      store,
      runStore,
      transport: createCaptureTransport(),
      senderConfig,
    })).rejects.toThrow("SUPABASE_SERVICE_ROLE_KEY=private");
    expect(runStore.finish).toHaveBeenCalledWith("run-202", {
      outcome: "failed",
      errorCode: "worker_failed",
      errorSafe: "A booking e-mail worker futása nem fejeződött be.",
    });
    expect(JSON.stringify((runStore.finish as ReturnType<typeof vi.fn>).mock.calls)).not.toContain("private");
  });

  it("a heartbeat naplózási hiba nem fedi el az eredeti worker-hibát", async () => {
    const store = storeFor([]);
    store.claim.mockRejectedValue(new Error("primary worker failure"));
    const runStore: BookingEmailWorkerRunStore = {
      start: vi.fn().mockResolvedValue("run-203"),
      finish: vi.fn().mockRejectedValue(new Error("heartbeat unavailable")),
    };
    await expect(runAuditedBookingEmailBatch({
      mode: "send",
      store,
      runStore,
      transport: createCaptureTransport(),
      senderConfig,
    })).rejects.toThrow("primary worker failure");
  });

  it("capture módban renderel, majd captured eredménnyel zár", async () => {
    const store = storeFor([job]);
    const transport = createCaptureTransport();
    const summary = await processBookingEmailBatch({ mode: "capture", store, transport, senderConfig });
    expect(summary).toMatchObject({ claimed: 1, captured: 1, sent: 0 });
    expect(transport.captured).toHaveLength(1);
    expect(store.complete).toHaveBeenCalledWith(expect.objectContaining({
      outboxId: job.id, leaseToken: job.leaseToken, result: "captured",
    }));
  });

  it("sikeres SMTP-küldést provider Message-ID-val zár", async () => {
    const store = storeFor([job]);
    const transport: EmailTransport = {
      send: vi.fn().mockResolvedValue({ outcome: "sent", providerMessageId: "provider-201" }),
    };
    const summary = await processBookingEmailBatch({ mode: "send", store, transport, senderConfig });
    expect(summary).toMatchObject({ claimed: 1, sent: 1 });
    expect(store.complete).toHaveBeenCalledWith(expect.objectContaining({
      result: "sent", providerMessageId: "provider-201",
    }));
  });

  it("átmeneti SMTP-hibát az előírt első retry időre ütemez", async () => {
    const store = storeFor([job]);
    const transport: EmailTransport = {
      send: vi.fn().mockRejectedValue({ code: "ETIMEDOUT", message: "raw private detail" }),
    };
    const summary = await processBookingEmailBatch({
      mode: "send",
      store,
      transport,
      senderConfig,
      now: () => new Date("2026-09-03T10:00:00Z"),
    });
    expect(summary).toMatchObject({ retry: 1, deadLetter: 0 });
    expect(store.complete).toHaveBeenCalledWith(expect.objectContaining({
      result: "retry",
      errorCode: "smtp_etimedout",
      errorSafe: "Átmeneti SMTP hálózati hiba.",
      nextAttemptAt: "2026-09-03T10:01:00.000Z",
    }));
    expect(JSON.stringify(store.complete.mock.calls)).not.toContain("raw private detail");
  });

  it("végleges SMTP-hibát dead letterrel zár", async () => {
    const store = storeFor([job]);
    const transport: EmailTransport = {
      send: vi.fn().mockRejectedValue({ code: "EAUTH", message: "SMTP_PASS=secret" }),
    };
    const summary = await processBookingEmailBatch({ mode: "send", store, transport, senderConfig });
    expect(summary).toMatchObject({ retry: 0, deadLetter: 1 });
    expect(store.complete).toHaveBeenCalledWith(expect.objectContaining({
      result: "dead_letter", errorCode: "smtp_auth", errorSafe: "Az SMTP hitelesítés sikertelen.",
    }));
    expect(JSON.stringify(store.complete.mock.calls)).not.toContain("SMTP_PASS=secret");
  });

  it("a nyolcadik próbálkozás előtt már nem ütemez új retryt", async () => {
    const store = storeFor([{ ...job, attempts: 7 }]);
    const transport: EmailTransport = { send: vi.fn().mockRejectedValue({ responseCode: 451 }) };
    const summary = await processBookingEmailBatch({ mode: "send", store, transport, senderConfig });
    expect(summary.deadLetter).toBe(1);
    expect(store.complete).toHaveBeenCalledWith(expect.objectContaining({
      result: "dead_letter", errorCode: "smtp_retry_exhausted", nextAttemptAt: undefined,
    }));
  });

  it("hibás payloadot küldés nélkül dead letterrel zár", async () => {
    const store = storeFor([{ ...job, payload: { ...payload, note: "nem kerülhet levélbe" } }]);
    const send = vi.fn();
    const summary = await processBookingEmailBatch({ mode: "send", store, transport: { send }, senderConfig });
    expect(summary.deadLetter).toBe(1);
    expect(send).not.toHaveBeenCalled();
    expect(store.complete).toHaveBeenCalledWith(expect.objectContaining({
      result: "dead_letter", errorCode: "payload_invalid",
    }));
  });

  it("scope-eltérés esetén nem küld levelet", async () => {
    const store = storeFor([{ ...job, scope: "series" }]);
    const send = vi.fn();
    await processBookingEmailBatch({ mode: "send", store, transport: { send }, senderConfig });
    expect(send).not.toHaveBeenCalled();
    expect(store.complete).toHaveBeenCalledWith(expect.objectContaining({ result: "dead_letter" }));
  });

  it("sikeres küldés utáni completion-hibánál nem minősíti át és nem küld újra", async () => {
    const complete = vi.fn<(completion: BookingEmailCompletion) => Promise<void>>()
      .mockRejectedValue(new Error("database unavailable"));
    const store = storeFor([job], complete);
    const send = vi.fn().mockResolvedValue({ outcome: "sent", providerMessageId: "provider-201" });
    await expect(processBookingEmailBatch({ mode: "send", store, transport: { send }, senderConfig }))
      .rejects.toThrow("database unavailable");
    expect(send).toHaveBeenCalledOnce();
    expect(complete).toHaveBeenCalledOnce();
    expect(complete).toHaveBeenCalledWith(expect.objectContaining({ result: "sent" }));
  });
});
