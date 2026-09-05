import { describe, expect, it } from "vitest";

import {
  bookingEmailMonitorAlerts,
  bookingEmailTimestamp,
  count,
  type BookingEmailMonitorSummary,
} from "./monitor";

const healthySummary: BookingEmailMonitorSummary = {
  pending_count: 0,
  retry_count: 0,
  sending_count: 0,
  dead_letter_count: 0,
  captured_count: 3,
  suppressed_count: 0,
  sent_count: 5,
  sent_24h_count: 2,
  due_count: 0,
  stale_sending_count: 0,
  stale_worker_run_count: 0,
  smtp_auth_error_24h_count: 0,
  oldest_due_at: null,
  last_sent_at: "2026-09-03T09:58:00Z",
  last_worker_started_at: "2026-09-03T09:59:00Z",
  last_worker_success_at: "2026-09-03T10:00:00Z",
  last_worker_failure_at: null,
  database_now: "2026-09-03T10:10:00Z",
};

describe("booking e-mail admin monitor", () => {
  it("egészséges állapotban nem jelez riasztást", () => {
    expect(bookingEmailMonitorAlerts(healthySummary)).toEqual([]);
  });

  it("dead lettert, stale lease-t és ismétlődő auth hibát kiemel", () => {
    const alerts = bookingEmailMonitorAlerts({
      ...healthySummary,
      dead_letter_count: "2",
      stale_sending_count: 1,
      stale_worker_run_count: 1,
      smtp_auth_error_24h_count: 3,
    });
    expect(alerts).toHaveLength(4);
    expect(alerts.every((alert) => alert.severity === "error")).toBe(true);
  });

  it("régi esedékes rekordot és hiányzó heartbeatot jelez", () => {
    const alerts = bookingEmailMonitorAlerts({
      ...healthySummary,
      due_count: 1,
      oldest_due_at: "2026-09-03T09:40:00Z",
      last_worker_success_at: null,
    });
    expect(alerts.map((alert) => alert.text)).toEqual([
      "A legrégebbi esedékes e-mail több mint 15 perce vár feldolgozásra.",
      "Még nincs sikeresen lezárt worker-futás.",
    ]);
  });

  it("a bigint stringeket biztonságosan számmá alakítja", () => {
    expect(count("12")).toBe(12);
    expect(count("hibás")).toBe(0);
  });

  it("Budapest időzónában formáz, hibás értéknél nem dob", () => {
    expect(bookingEmailTimestamp("2026-09-03T08:00:00Z")).toContain("10:00:00");
    expect(bookingEmailTimestamp("invalid")).toBe("–");
    expect(bookingEmailTimestamp(null)).toBe("–");
  });
});
