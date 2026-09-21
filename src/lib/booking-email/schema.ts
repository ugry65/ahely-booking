export const BOOKING_EMAIL_PAYLOAD_VERSION = 1 as const;
export const BOOKING_EMAIL_EVENT_TYPES = ["booking.created", "booking.updated", "booking.cancelled"] as const;
export const BOOKING_EMAIL_SCOPES = ["single", "occurrence", "following", "series"] as const;

export type BookingEmailEventType = (typeof BOOKING_EMAIL_EVENT_TYPES)[number];
export type BookingEmailScope = (typeof BOOKING_EMAIL_SCOPES)[number];

export type BookingEmailState = {
  roomName: string;
  startAt: string;
  endAt: string;
  useType: "individual" | "group";
  bookingTitle?: string;
};

export type BookingEmailPayloadV1 = BookingEmailState & {
  recipientName: string;
  scope: BookingEmailScope;
  affectedCount: number;
  firstStartAt: string;
  lastEndAt: string;
  performedByAdmin: boolean;
  cancellationReason?: string;
  before?: BookingEmailState;
  after?: BookingEmailState;
};

export type BookingEmailJob = {
  id: string;
  eventType: BookingEmailEventType;
  recipientEmail: string;
  payloadVersion: number;
  payload: unknown;
};

const PAYLOAD_KEYS = new Set([
  "recipient_name", "room_name", "start_at", "end_at", "use_type", "booking_title",
  "scope", "affected_count", "first_start_at", "last_end_at", "performed_by_admin",
  "cancellation_reason", "before", "after",
]);
const STATE_KEYS = new Set(["room_name", "start_at", "end_at", "use_type", "booking_title"]);

function record(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Érvénytelen ${label}.`);
  }
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, allowed: Set<string>, label: string) {
  const unexpected = Object.keys(value).find((key) => !allowed.has(key));
  if (unexpected) throw new Error(`Nem támogatott ${label} mező: ${unexpected}.`);
}

function text(value: unknown, label: string, maxLength = 300): string {
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) {
    throw new Error(`Érvénytelen ${label}.`);
  }
  return value.trim();
}

function optionalText(value: unknown, label: string, maxLength = 1000): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return text(value, label, maxLength);
}

function instant(value: unknown, label: string): string {
  const parsed = text(value, label, 80);
  if (!Number.isFinite(Date.parse(parsed))) throw new Error(`Érvénytelen ${label}.`);
  return parsed;
}

function useType(value: unknown): BookingEmailState["useType"] {
  if (value !== "individual" && value !== "group") throw new Error("Érvénytelen használattípus.");
  return value;
}

function state(value: unknown, label: string, strictKeys = true): BookingEmailState {
  const source = record(value, label);
  if (strictKeys) exactKeys(source, STATE_KEYS, label);
  const startAt = instant(source.start_at, `${label} kezdési idő`);
  const endAt = instant(source.end_at, `${label} befejezési idő`);
  if (Date.parse(endAt) <= Date.parse(startAt)) throw new Error(`Érvénytelen ${label} időtartam.`);
  return {
    roomName: text(source.room_name, `${label} helyiségnév`),
    startAt,
    endAt,
    useType: useType(source.use_type),
    bookingTitle: optionalText(source.booking_title, `${label} foglalási cím`, 100),
  };
}

export function parseBookingEmailPayload(
  eventType: BookingEmailEventType,
  payloadVersion: number,
  value: unknown,
): BookingEmailPayloadV1 {
  if (payloadVersion !== BOOKING_EMAIL_PAYLOAD_VERSION) {
    throw new Error(`Nem támogatott booking e-mail payload-verzió: ${payloadVersion}.`);
  }

  const source = record(value, "booking e-mail payload");
  exactKeys(source, PAYLOAD_KEYS, "booking e-mail payload");
  const current = state(source, "booking e-mail payload", false);
  if (!BOOKING_EMAIL_SCOPES.includes(source.scope as BookingEmailScope)) {
    throw new Error("Érvénytelen booking e-mail scope.");
  }
  if (!Number.isInteger(source.affected_count) || (source.affected_count as number) < 1) {
    throw new Error("Érvénytelen érintett alkalomszám.");
  }
  if (typeof source.performed_by_admin !== "boolean") {
    throw new Error("Érvénytelen adminművelet-jelzés.");
  }

  const firstStartAt = instant(source.first_start_at, "első érintett kezdés");
  const lastEndAt = instant(source.last_end_at, "utolsó érintett befejezés");
  if (Date.parse(lastEndAt) <= Date.parse(firstStartAt)) {
    throw new Error("Érvénytelen összesített időtartam.");
  }

  const before = source.before === undefined ? undefined : state(source.before, "korábbi állapot");
  const after = source.after === undefined ? undefined : state(source.after, "új állapot");
  if (eventType === "booking.updated" && (!before || !after)) {
    throw new Error("Módosítási e-mailhez korábbi és új állapot szükséges.");
  }
  if (eventType !== "booking.updated" && (before || after)) {
    throw new Error("Előző/új állapot csak módosítási e-mailben szerepelhet.");
  }
  if (eventType !== "booking.cancelled" && source.cancellation_reason !== undefined) {
    throw new Error("Lemondási ok csak lemondási e-mailben szerepelhet.");
  }

  return {
    ...current,
    recipientName: text(source.recipient_name, "címzett neve"),
    scope: source.scope as BookingEmailScope,
    affectedCount: source.affected_count as number,
    firstStartAt,
    lastEndAt,
    performedByAdmin: source.performed_by_admin,
    cancellationReason: optionalText(source.cancellation_reason, "lemondási ok"),
    before,
    after,
  };
}

export function parseBookingEmailJob(job: BookingEmailJob): BookingEmailPayloadV1 {
  if (!BOOKING_EMAIL_EVENT_TYPES.includes(job.eventType)) throw new Error("Érvénytelen booking e-mail eseménytípus.");
  return parseBookingEmailPayload(job.eventType, job.payloadVersion, job.payload);
}
