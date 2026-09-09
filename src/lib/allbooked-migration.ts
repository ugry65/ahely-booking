import { createHash } from "node:crypto";

export type AllBookedDryRunIssue = {
  line: number;
  code: string;
  message: string;
};

export type NormalizedAllBookedUser = {
  email: string;
  firstName: string;
  lastName: string;
  phone: string | null;
  accessTags: string[];
};

export type NormalizedAllBookedBooking = {
  sourceFingerprint: string;
  line: number;
  holderEmail: string;
  roomSource: string;
  roomTarget: string;
  startLocal: string;
  endLocal: string;
  durationMinutes: number;
  bookingTitle: string | null;
};

export type AllBookedDryRunResult = {
  valid: boolean;
  users: NormalizedAllBookedUser[];
  bookings: NormalizedAllBookedBooking[];
  ignoredPricingFields: string[];
  issues: AllBookedDryRunIssue[];
  summary: {
    sourceRows: number;
    normalizedUsers: number;
    normalizedBookings: number;
    totalMinutes: number;
    totalHours: number;
    bookingsByRoom: Record<string, number>;
    bookingsByUser: Record<string, number>;
  };
};

const REQUIRED_COLUMNS = [
  "Scheduled start",
  "End",
  "Duration (minutes)",
  "Booking type",
  "Holder first name",
  "Holder last name",
  "Holder telephone",
  "Holder email",
  "Holder tags",
  "Spaces",
  "Spaces count",
  "Add-Ons count",
  "Add-Ons",
  "Booking title",
  "Notes (Custom field 1)",
] as const;

export const IGNORED_ALLBOOKED_PRICING_FIELDS = [
  "Total booking price",
  "Payment status",
  "Line item price",
  "Gateway charge reference",
] as const;

function parseDelimited(text: string, delimiter = ";") {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === delimiter) {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }

  if (field.length || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }

  return rows.filter((item) => item.some((value) => value.trim()));
}

function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

function normalizePhone(value: string) {
  const cleaned = value.trim().replace(/^tel:\s*/i, "").replace(/[\s()-]/g, "");
  if (!cleaned) return null;
  if (/^06\d{9}$/.test(cleaned)) return `+36${cleaned.slice(2)}`;
  if (/^36\d{9}$/.test(cleaned)) return `+${cleaned}`;
  if (/^\+36\d{9}$/.test(cleaned)) return cleaned;
  return value.trim();
}

function parseTags(value: string) {
  return value
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean)
    .filter((tag) => !/^\d+(?:[.,]\d+)?$/.test(tag));
}

function isLocalDateTime(value: string) {
  return /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(value.trim());
}

function localToUtcMs(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const [, year, month, day, hour, minute] = match;
  // Dry-run only: this helper is used solely for duration consistency, where
  // the same local offset applies to the start/end values in the supported sample.
  return Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute));
}

function fingerprint(parts: string[]) {
  return createHash("sha256").update(parts.join("\u001f"), "utf8").digest("hex");
}

function nonEmpty(value: string | undefined) {
  return String(value ?? "").trim();
}

export function buildAllBookedDryRun(
  csvText: string,
  roomMapping: Record<string, string>,
): AllBookedDryRunResult {
  const rows = parseDelimited(csvText, ";");
  const issues: AllBookedDryRunIssue[] = [];
  if (rows.length < 2) {
    return {
      valid: false,
      users: [],
      bookings: [],
      ignoredPricingFields: [...IGNORED_ALLBOOKED_PRICING_FIELDS],
      issues: [{ line: 1, code: "empty_source", message: "Az export nem tartalmaz importálható adatsort." }],
      summary: { sourceRows: 0, normalizedUsers: 0, normalizedBookings: 0, totalMinutes: 0, totalHours: 0, bookingsByRoom: {}, bookingsByUser: {} },
    };
  }

  const headers = rows[0].map((header) => header.trim());
  const missing = REQUIRED_COLUMNS.filter((name) => !headers.includes(name));
  if (missing.length) {
    return {
      valid: false,
      users: [],
      bookings: [],
      ignoredPricingFields: [...IGNORED_ALLBOOKED_PRICING_FIELDS],
      issues: [{ line: 1, code: "missing_columns", message: `Hiányzó kötelező oszlopok: ${missing.join(", ")}.` }],
      summary: { sourceRows: rows.length - 1, normalizedUsers: 0, normalizedBookings: 0, totalMinutes: 0, totalHours: 0, bookingsByRoom: {}, bookingsByUser: {} },
    };
  }

  const column = (name: string) => headers.indexOf(name);
  const value = (row: string[], name: string) => nonEmpty(row[column(name)]);
  const users = new Map<string, NormalizedAllBookedUser>();
  const bookings: NormalizedAllBookedBooking[] = [];
  const fingerprints = new Set<string>();

  for (let offset = 1; offset < rows.length; offset += 1) {
    const row = rows[offset];
    const line = offset + 1;
    const email = normalizeEmail(value(row, "Holder email"));
    const firstName = value(row, "Holder first name");
    const lastName = value(row, "Holder last name");
    const phone = normalizePhone(value(row, "Holder telephone"));
    const bookingType = value(row, "Booking type");
    const roomSource = value(row, "Spaces");
    const roomTarget = roomMapping[roomSource];
    const startLocal = value(row, "Scheduled start");
    const endLocal = value(row, "End");
    const durationMinutes = Number(value(row, "Duration (minutes)"));
    const spacesCount = Number(value(row, "Spaces count"));
    const addOnsCount = Number(value(row, "Add-Ons count") || "0");
    const addOns = value(row, "Add-Ons");
    const note = value(row, "Notes (Custom field 1)");
    const bookingTitle = value(row, "Booking title") || null;

    if (!/^\S+@\S+\.\S+$/.test(email) || !firstName || !lastName) {
      issues.push({ line, code: "invalid_user", message: "Hiányzó vagy hibás user név/e-mail." });
      continue;
    }
    if (bookingType !== "User booking") {
      issues.push({ line, code: "unsupported_booking_type", message: `Nem támogatott booking type: ${bookingType || "(üres)"}.` });
      continue;
    }
    if (!roomSource || !roomTarget) {
      issues.push({ line, code: "unknown_room", message: `Nincs explicit room mapping: ${roomSource || "(üres)"}.` });
      continue;
    }
    if (spacesCount !== 1) {
      issues.push({ line, code: "unsupported_space_count", message: `A Spaces count értéke nem 1: ${String(spacesCount)}.` });
      continue;
    }
    if (addOnsCount !== 0 || addOns) {
      issues.push({ line, code: "unsupported_addons", message: "Az első migrációs scope-ban Add-On nem támogatott." });
      continue;
    }
    if (!isLocalDateTime(startLocal) || !isLocalDateTime(endLocal) || !Number.isInteger(durationMinutes) || durationMinutes <= 0) {
      issues.push({ line, code: "invalid_time", message: "Hibás kezdés, befejezés vagy időtartam." });
      continue;
    }
    const startMs = localToUtcMs(startLocal);
    const endMs = localToUtcMs(endLocal);
    if (startMs === null || endMs === null || endMs <= startMs || (endMs - startMs) / 60_000 !== durationMinutes) {
      issues.push({ line, code: "duration_mismatch", message: "A kezdés/befejezés és a Duration (minutes) nem egyezik." });
      continue;
    }
    if (note) {
      issues.push({ line, code: "note_requires_review", message: "A megjegyzés nem másolható automatikusan; kézi adatvédelmi felülvizsgálat szükséges." });
      continue;
    }

    const normalizedUser: NormalizedAllBookedUser = {
      email,
      firstName,
      lastName,
      phone,
      accessTags: parseTags(value(row, "Holder tags")),
    };
    const existingUser = users.get(email);
    if (existingUser && JSON.stringify(existingUser) !== JSON.stringify(normalizedUser)) {
      issues.push({ line, code: "inconsistent_user", message: `Ugyanahhoz az e-mailhez eltérő user adatok tartoznak: ${email}.` });
      continue;
    }
    users.set(email, normalizedUser);

    const sourceFingerprint = fingerprint([email, roomSource, startLocal, endLocal, bookingType]);
    if (fingerprints.has(sourceFingerprint)) {
      issues.push({ line, code: "duplicate_booking", message: "Duplikált forrásfoglalás a normalizált kulcs alapján." });
      continue;
    }
    fingerprints.add(sourceFingerprint);

    bookings.push({
      sourceFingerprint,
      line,
      holderEmail: email,
      roomSource,
      roomTarget,
      startLocal,
      endLocal,
      durationMinutes,
      bookingTitle,
    });
  }

  const bookingsByRoom: Record<string, number> = {};
  const bookingsByUser: Record<string, number> = {};
  let totalMinutes = 0;
  for (const booking of bookings) {
    bookingsByRoom[booking.roomTarget] = (bookingsByRoom[booking.roomTarget] ?? 0) + 1;
    bookingsByUser[booking.holderEmail] = (bookingsByUser[booking.holderEmail] ?? 0) + 1;
    totalMinutes += booking.durationMinutes;
  }

  return {
    valid: issues.length === 0,
    users: [...users.values()],
    bookings,
    ignoredPricingFields: [...IGNORED_ALLBOOKED_PRICING_FIELDS],
    issues,
    summary: {
      sourceRows: rows.length - 1,
      normalizedUsers: users.size,
      normalizedBookings: bookings.length,
      totalMinutes,
      totalHours: totalMinutes / 60,
      bookingsByRoom,
      bookingsByUser,
    },
  };
}
