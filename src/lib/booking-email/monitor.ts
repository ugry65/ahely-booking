export type CountValue = number | string;

export type BookingEmailMonitorSummary = {
  pending_count: CountValue;
  retry_count: CountValue;
  sending_count: CountValue;
  dead_letter_count: CountValue;
  captured_count: CountValue;
  suppressed_count: CountValue;
  sent_count: CountValue;
  sent_24h_count: CountValue;
  due_count: CountValue;
  stale_sending_count: CountValue;
  stale_worker_run_count: CountValue;
  smtp_auth_error_24h_count: CountValue;
  oldest_due_at: string | null;
  last_sent_at: string | null;
  last_worker_started_at: string | null;
  last_worker_success_at: string | null;
  last_worker_failure_at: string | null;
  database_now: string;
};

export type BookingEmailProblemItem = {
  outbox_id: string;
  problem_kind: "dead_letter" | "stale_sending" | "retry";
  event_type: string;
  scope: string;
  status: string;
  attempts: number;
  next_attempt_at: string;
  lease_expires_at: string | null;
  last_error_code: string | null;
  last_error_safe: string | null;
  created_at: string;
  updated_at: string;
};

export type BookingEmailWorkerRun = {
  run_id: string;
  mode: "capture" | "send";
  status: "running" | "success" | "failed";
  claimed_count: number;
  sent_count: number;
  captured_count: number;
  retry_count: number;
  dead_letter_count: number;
  error_code: string | null;
  error_safe: string | null;
  started_at: string;
  finished_at: string | null;
};

export type BookingEmailMonitorAlert = {
  severity: "error" | "warning";
  text: string;
};

export function count(value: CountValue): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function ageMinutes(timestamp: string | null, now: number): number | null {
  if (!timestamp) return null;
  const value = Date.parse(timestamp);
  return Number.isFinite(value) ? Math.max(0, (now - value) / 60_000) : null;
}

export function bookingEmailMonitorAlerts(
  summary: BookingEmailMonitorSummary,
): BookingEmailMonitorAlert[] {
  const alerts: BookingEmailMonitorAlert[] = [];
  const now = Date.parse(summary.database_now);
  const safeNow = Number.isFinite(now) ? now : Date.now();

  if (count(summary.dead_letter_count) > 0) {
    alerts.push({ severity: "error", text: `${count(summary.dead_letter_count)} végleg sikertelen e-mail vár vizsgálatra.` });
  }
  if (count(summary.stale_sending_count) > 0) {
    alerts.push({ severity: "error", text: `${count(summary.stale_sending_count)} e-mail lejárt worker lease-ben maradt.` });
  }
  if (count(summary.stale_worker_run_count) > 0) {
    alerts.push({ severity: "error", text: `${count(summary.stale_worker_run_count)} worker-futás több mint 30 perce nem zárult le.` });
  }
  if (count(summary.smtp_auth_error_24h_count) >= 3) {
    alerts.push({ severity: "error", text: "Ismétlődő SMTP-hitelesítési hiba történt az elmúlt 24 órában." });
  }

  const dueAge = ageMinutes(summary.oldest_due_at, safeNow);
  if (count(summary.due_count) > 0 && dueAge !== null && dueAge >= 15) {
    alerts.push({ severity: "warning", text: "A legrégebbi esedékes e-mail több mint 15 perce vár feldolgozásra." });
  }

  const heartbeatAge = ageMinutes(summary.last_worker_success_at, safeNow);
  if (heartbeatAge === null) {
    alerts.push({ severity: "warning", text: "Még nincs sikeresen lezárt worker-futás." });
  } else if (heartbeatAge >= 30) {
    alerts.push({ severity: "warning", text: "A worker utolsó sikeres heartbeatja több mint 30 perces." });
  }

  const failureAt = summary.last_worker_failure_at ? Date.parse(summary.last_worker_failure_at) : Number.NaN;
  const successAt = summary.last_worker_success_at ? Date.parse(summary.last_worker_success_at) : Number.NaN;
  if (Number.isFinite(failureAt) && (!Number.isFinite(successAt) || failureAt > successAt)) {
    alerts.push({ severity: "warning", text: "A legutóbbi lezárt worker-futás hibás volt." });
  }

  return alerts;
}

export function bookingEmailTimestamp(value: string | null): string {
  if (!value) return "–";
  const timestamp = new Date(value);
  if (Number.isNaN(timestamp.getTime())) return "–";
  return new Intl.DateTimeFormat("hu-HU", {
    timeZone: "Europe/Budapest",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(timestamp);
}

export function bookingEmailEventLabel(value: string): string {
  return ({
    "booking.created": "Létrehozás",
    "booking.updated": "Módosítás",
    "booking.cancelled": "Lemondás",
  } as Record<string, string>)[value] ?? value;
}

export function bookingEmailScopeLabel(value: string): string {
  return ({
    single: "Egyedi",
    occurrence: "Egy alkalom",
    following: "Ettől kezdve",
    series: "Teljes sorozat",
  } as Record<string, string>)[value] ?? value;
}

export function bookingEmailRunStatusLabel(value: BookingEmailWorkerRun["status"]): string {
  return ({ running: "Fut", success: "Sikeres", failed: "Hibás" })[value];
}
