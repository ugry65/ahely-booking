import { describe, expect, it } from "vitest";
import { parseCancelBookingForm, parseUpdateBookingForm } from "./booking-operation-form";

const valid = { bookingId: "31000000-0000-0000-0000-000000000001", expectedUpdatedAt: "2026-08-17T10:00:00.000Z", roomId: "11000000-0000-0000-0000-000000000002", date: "2026-09-10", startTime: "09:00", endTime: "10:00", useType: "individual", note: " Megjegyzés ", idempotencyKey: "32000000-0000-0000-0000-000000000001" };

describe("booking operation forms", () => {
  it("érvényes módosítást RPC-adatokká alakít", () => expect(parseUpdateBookingForm(valid)).toMatchObject({ ok: true, value: { bookingId: valid.bookingId, expectedUpdatedAt: valid.expectedUpdatedAt, note: "Megjegyzés" } }));
  it("elutasítja a hibás verziót és foglalásazonosítót", () => {
    expect(parseUpdateBookingForm({ ...valid, expectedUpdatedAt: "hibás" }).ok).toBe(false);
    expect(parseUpdateBookingForm({ ...valid, bookingId: "hibás" }).ok).toBe(false);
  });
  it("érvényes lemondást normalizál", () => expect(parseCancelBookingForm({ bookingId: valid.bookingId, idempotencyKey: valid.idempotencyKey, reason: "  Betegség  " })).toEqual({ ok: true, value: { bookingId: valid.bookingId, idempotencyKey: valid.idempotencyKey, reason: "Betegség" } }));
  it("elutasítja a manipulált kulcsot és túl hosszú indokot", () => {
    expect(parseCancelBookingForm({ bookingId: valid.bookingId, idempotencyKey: "hibás", reason: "" }).ok).toBe(false);
    expect(parseCancelBookingForm({ bookingId: valid.bookingId, idempotencyKey: valid.idempotencyKey, reason: "x".repeat(501) }).ok).toBe(false);
  });
});
