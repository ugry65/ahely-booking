import { describe, expect, it, vi } from "vitest";

import { handleBookingEmailWorkerRequest } from "./worker-route";

function request(token?: string): Request {
  return new Request("https://booking.example/api/internal/booking-email-worker", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
}

describe("booking e-mail worker Route Handler", () => {
  it("hibás tokennél 401-et ad és nem hoz létre runtime-ot", async () => {
    const createRuntime = vi.fn();
    const response = await handleBookingEmailWorkerRequest(request("wrong"), {
      getCronSecret: () => "correct",
      createRuntime,
    });
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(createRuntime).not.toHaveBeenCalled();
  });

  it("hiányzó CRON_SECRET esetén biztonságos 503-at ad", async () => {
    const response = await handleBookingEmailWorkerRequest(request("anything"), {
      getCronSecret: () => { throw new Error("CRON_SECRET raw config"); },
      createRuntime: vi.fn(),
    });
    expect(response.status).toBe(503);
    expect(JSON.stringify(await response.json())).not.toContain("raw config");
  });

  it("disabled módban nem hív workert és nem claimel", async () => {
    const run = vi.fn();
    const response = await handleBookingEmailWorkerRequest(request("correct"), {
      getCronSecret: () => "correct",
      createRuntime: () => ({ mode: "disabled", run }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      mode: "disabled", claimed: 0, sent: 0, captured: 0, retry: 0, deadLetter: 0,
    });
    expect(run).not.toHaveBeenCalled();
  });

  it("capture runtime eredményét csak számlálókkal adja vissza", async () => {
    const run = vi.fn().mockResolvedValue({
      mode: "capture", claimed: 2, sent: 0, captured: 2, retry: 0, deadLetter: 0,
    });
    const response = await handleBookingEmailWorkerRequest(request("correct"), {
      getCronSecret: () => "correct",
      createRuntime: () => ({ mode: "capture", run }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ mode: "capture", claimed: 2, captured: 2 });
    expect(run).toHaveBeenCalledOnce();
  });

  it("hibás runtime-konfigurációt nyers részlet nélkül jelez", async () => {
    const response = await handleBookingEmailWorkerRequest(request("correct"), {
      getCronSecret: () => "correct",
      createRuntime: () => { throw new Error("SMTP_PASS=secret"); },
    });
    expect(response.status).toBe(503);
    const body = JSON.stringify(await response.json());
    expect(body).toBe('{"error":"worker_not_configured"}');
    expect(body).not.toContain("secret");
  });

  it("worker vagy completion hibát általános 500-zal zár", async () => {
    const response = await handleBookingEmailWorkerRequest(request("correct"), {
      getCronSecret: () => "correct",
      createRuntime: () => ({
        mode: "send",
        run: vi.fn().mockRejectedValue(new Error("recipient and provider response")),
      }),
    });
    expect(response.status).toBe(500);
    const body = JSON.stringify(await response.json());
    expect(body).toBe('{"error":"worker_failed"}');
    expect(body).not.toContain("recipient");
  });
});
