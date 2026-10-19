import { describe, expect, it } from "vitest";
import { bookingHourParts, cancellationPreview } from "./partial-booking-cancellation";
const at = (s: string) => `2026-10-20T${s}:00.000Z`;
describe("partial cancellation planning (server remains authoritative)", () => {
  it("shows seven hours of an existing block", () => expect(bookingHourParts(at("08:00"), at("15:00"))).toHaveLength(7));
  it("keeps 8–10 and 12–15", () => expect(cancellationPreview(at("08:00"), at("15:00"), [{ start: at("10:00"), end: at("12:00") }])).toEqual({ ok: true, remaining: [{ start: at("08:00"), end: at("10:00") }, { start: at("12:00"), end: at("15:00") }] }));
  it("supports adjacent selected hours", () => expect(cancellationPreview(at("08:00"), at("15:00"), [{ start: at("10:00"), end: at("11:00") }, { start: at("11:00"), end: at("12:00") }]).ok).toBe(true));
  it("supports disconnected selections", () => expect(cancellationPreview(at("08:00"), at("15:00"), [{ start: at("09:00"), end: at("10:00") }, { start: at("12:00"), end: at("13:00") }]).ok).toBe(true));
  it("preserves a half-hour end choice", () => expect(bookingHourParts(at("08:30"), at("11:00"))).toHaveLength(3));
  it("rejects a half-hour remaining booking", () => expect(cancellationPreview(at("08:30"), at("11:00"), [{ start: at("09:00"), end: at("11:00") }]).ok).toBe(false));
  it("supports entire remaining fragment cancellation", () => expect(cancellationPreview(at("08:00"), at("10:00"), [{ start: at("08:00"), end: at("10:00") }])).toEqual({ ok: true, remaining: [] }));
  it("rejects empty, overlapping, outside and malformed selection", () => {
    for (const ranges of [[], [{ start: at("07:00"), end: at("10:00") }], [{ start: "bad", end: at("10:00") }], [{ start: at("09:00"), end: at("11:00") }, { start: at("10:00"), end: at("12:00") }]]) expect(cancellationPreview(at("08:00"), at("15:00"), ranges).ok).toBe(false);
  });
});
