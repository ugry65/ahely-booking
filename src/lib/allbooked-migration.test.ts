import { describe, expect, it } from "vitest";

import {
  ALLBOOKED_ROOM_MAPPING,
  approvedBudapestLocalToIso,
  buildAllBookedDryRun,
  IGNORED_ALLBOOKED_PRICING_FIELDS,
  validatePappDalmaImport,
} from "./allbooked-migration";

const header = [
  "Scheduled start",
  "End",
  "Duration (minutes)",
  "Spaces count",
  "Add-Ons count",
  "Booking type",
  "Booking title",
  "Total booking price",
  "Payment status",
  "Line item type",
  "Line item name",
  "Line item price",
  "Add-On quantity",
  "Holder first name",
  "Holder last name",
  "Holder organization",
  "Holder telephone",
  "Holder email",
  "Holder tags",
  "Created",
  "Gateway charge reference",
  "Spaces",
  "Add-Ons",
  "Notes (Custom field 1)",
].join(";");

function row(overrides: Partial<Record<string, string>> = {}) {
  const values: Record<string, string> = {
    "Scheduled start": "2026-09-03 09:30",
    End: "2026-09-03 10:30",
    "Duration (minutes)": "60",
    "Spaces count": "1",
    "Add-Ons count": "0",
    "Booking type": "User booking",
    "Booking title": "",
    "Total booking price": "1 700,00",
    "Payment status": "Unpaid",
    "Line item type": "Space",
    "Line item name": "Forrás tér",
    "Line item price": "1 700,00",
    "Add-On quantity": "",
    "Holder first name": "Dalma ",
    "Holder last name": "Papp",
    "Holder organization": "",
    "Holder telephone": "Tel: 06 30 733 7981",
    "Holder email": "pappdalma17@gmail.com",
    "Holder tags": "1700, Forrás",
    Created: "2026-09-01 18:12",
    "Gateway charge reference": "",
    Spaces: "Forrás tér",
    "Add-Ons": "",
    "Notes (Custom field 1)": "",
    ...overrides,
  };
  return header.split(";").map((name) => values[name] ?? "").join(";");
}

describe("buildAllBookedDryRun", () => {
  it("normalizes the representative Papp Dalma row and excludes legacy pricing", () => {
    const result = buildAllBookedDryRun(`${header}\n${row()}\n`, { "Forrás tér": "Forrás tér" });

    expect(result.valid).toBe(true);
    expect(result.summary).toMatchObject({
      sourceRows: 1,
      normalizedUsers: 1,
      normalizedBookings: 1,
      totalMinutes: 60,
      totalHours: 1,
    });
    expect(result.users[0]).toEqual({
      email: "pappdalma17@gmail.com",
      firstName: "Dalma",
      lastName: "Papp",
      phone: "+36307337981",
      accessTags: ["Forrás"],
    });
    expect(result.bookings[0]).toMatchObject({
      holderEmail: "pappdalma17@gmail.com",
      roomSource: "Forrás tér",
      roomTarget: "Forrás tér",
      startLocal: "2026-09-03 09:30",
      endLocal: "2026-09-03 10:30",
      durationMinutes: 60,
      bookingTitle: null,
    });
    expect(result.ignoredPricingFields).toEqual([...IGNORED_ALLBOOKED_PRICING_FIELDS]);
    expect(JSON.stringify(result)).not.toContain("1 700,00");
    expect(result.users[0].accessTags).not.toContain("1700");
  });

  it("aggregates bookings and hours without comparing source money values", () => {
    const csv = [
      header,
      row(),
      row({ "Scheduled start": "2026-09-08 11:30", End: "2026-09-08 13:00", "Duration (minutes)": "90", "Total booking price": "2 550,00", "Line item price": "2 550,00" }),
    ].join("\n");
    const result = buildAllBookedDryRun(csv, { "Forrás tér": "Forrás tér" });

    expect(result.valid).toBe(true);
    expect(result.summary.normalizedBookings).toBe(2);
    expect(result.summary.totalMinutes).toBe(150);
    expect(result.summary.totalHours).toBe(2.5);
    expect(result.summary.bookingsByRoom).toEqual({ "Forrás tér": 2 });
    expect(result.summary.bookingsByUser).toEqual({ "pappdalma17@gmail.com": 2 });
  });

  it("fails closed on an unknown room mapping", () => {
    const result = buildAllBookedDryRun(`${header}\n${row()}\n`, {});
    expect(result.valid).toBe(false);
    expect(result.issues).toEqual([
      expect.objectContaining({ code: "unknown_room", line: 2 }),
    ]);
    expect(result.bookings).toHaveLength(0);
  });

  it("does not silently copy notes", () => {
    const result = buildAllBookedDryRun(`${header}\n${row({ "Notes (Custom field 1)": "érzékeny megjegyzés" })}\n`, { "Forrás tér": "Forrás tér" });
    expect(result.valid).toBe(false);
    expect(result.issues[0].code).toBe("note_requires_review");
  });

  it("detects duplicate source bookings idempotently", () => {
    const same = row();
    const result = buildAllBookedDryRun(`${header}\n${same}\n${same}\n`, { "Forrás tér": "Forrás tér" });
    expect(result.valid).toBe(false);
    expect(result.summary.normalizedBookings).toBe(1);
    expect(result.issues).toEqual([
      expect.objectContaining({ code: "duplicate_booking", line: 3 }),
    ]);
  });

  it("rejects mismatched duration", () => {
    const result = buildAllBookedDryRun(`${header}\n${row({ "Duration (minutes)": "90" })}\n`, { "Forrás tér": "Forrás tér" });
    expect(result.valid).toBe(false);
    expect(result.issues[0].code).toBe("duration_mismatch");
  });
});

describe("approved Papp Dalma staging import gate", () => {
  it("accepts exactly the approved 21 booking distribution", () => {
    const dates = ["03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14", "15", "16", "17"];
    const rows = Array.from({ length: 21 }, (_, index) => {
      const duration = index >= 19 ? 90 : 60;
      const day = dates[index % dates.length];
      const hour = 8 + Math.floor(index / dates.length) * 2;
      const endHour = duration === 60 ? hour + 1 : hour + 1;
      const endMinute = duration === 60 ? "00" : "30";
      return row({
        "Scheduled start": `2026-09-${day} ${String(hour).padStart(2, "0")}:00`,
        End: `2026-09-${day} ${String(endHour).padStart(2, "0")}:${endMinute}`,
        "Duration (minutes)": String(duration),
      });
    });
    const result = buildAllBookedDryRun([header, ...rows].join("\n"), ALLBOOKED_ROOM_MAPPING);
    expect(validatePappDalmaImport(result).valid).toBe(true);
  });

  it("converts only the approved CEST wall-time range", () => {
    expect(approvedBudapestLocalToIso("2026-09-03 09:30")).toBe("2026-09-03T09:30:00+02:00");
    expect(() => approvedBudapestLocalToIso("2026-10-25 02:30")).toThrow(/tartományon/);
  });
});
