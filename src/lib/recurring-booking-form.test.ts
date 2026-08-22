import { describe, expect, it } from "vitest";
import { parseRecurringBookingForm } from "./recurring-booking-form";

const valid = { roomId: "11000000-0000-0000-0000-000000000002", date: "2026-09-10", startTime: "09:00", endTime: "10:00", useType: "individual", note: " Sorozat ", bookingTitle: " Heti konzultáció ", idempotencyKey: "34000000-0000-0000-0000-000000000001", frequency: "weekly", conflictPolicy: "create_available", endMode: "count", occurrenceCount: "6", endsOn: "", exceptionDates: "2026-09-17, 2026-09-24\n2026-09-17" };

describe("recurring booking form", () => {
  it("darabszámos sorozatot normalizál, továbbviszi a címet és deduplikálja a kivételdátumokat", () => expect(parseRecurringBookingForm(valid)).toMatchObject({ ok: true, value: { occurrenceCount: 6, endsOn: null, exceptionDates: ["2026-09-17", "2026-09-24"], note: "Sorozat", bookingTitle: "Heti konzultáció" } }));
  it("végdátumos sorozatnál nullázza a darabszámot", () => expect(parseRecurringBookingForm({ ...valid, endMode: "date", endsOn: "2027-09-10", occurrenceCount: "6" })).toMatchObject({ ok: true, value: { endsOn: "2027-09-10", occurrenceCount: null } }));
  it("elutasítja a 366 napon túli végdátumot és a 400 feletti darabszámot", () => {
    expect(parseRecurringBookingForm({ ...valid, endMode: "date", endsOn: "2027-09-12" }).ok).toBe(false);
    expect(parseRecurringBookingForm({ ...valid, occurrenceCount: "401" }).ok).toBe(false);
  });
  it("pontosan 366 napos sorozatot még elfogad", () => {
    expect(parseRecurringBookingForm({ ...valid, endMode: "date", endsOn: "2027-09-11" })).toMatchObject({ ok: true, value: { endsOn: "2027-09-11" } });
  });
  it("elutasítja a sorozaton kívüli vagy hibás kivételdátumot", () => {
    expect(parseRecurringBookingForm({ ...valid, endMode: "date", endsOn: "2026-10-01", exceptionDates: "2026-10-02" }).ok).toBe(false);
    expect(parseRecurringBookingForm({ ...valid, exceptionDates: "2026-09-09" }).ok).toBe(false);
    expect(parseRecurringBookingForm({ ...valid, exceptionDates: "2026-02-30" }).ok).toBe(false);
  });
  it("száznál több különböző kivételdátumot elutasít", () => {
    const exceptionDates = Array.from({ length: 101 }, (_, index) => new Date(Date.UTC(2026, 8, 10 + index)).toISOString().slice(0, 10)).join(",");
    expect(parseRecurringBookingForm({ ...valid, exceptionDates }).ok).toBe(false);
  });
  it("elutasítja az ismeretlen gyakoriságot és konfliktuspolitikát", () => {
    expect(parseRecurringBookingForm({ ...valid, frequency: "yearly" }).ok).toBe(false);
    expect(parseRecurringBookingForm({ ...valid, conflictPolicy: "overwrite" }).ok).toBe(false);
  });
});
