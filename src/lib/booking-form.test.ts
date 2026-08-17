import { describe, expect, it } from "vitest";
import { budapestLocalToIso, isValidDate, parseBookingForm } from "./booking-form";
const valid = { roomId: "11000000-0000-0000-0000-000000000002", date: "2026-09-10", startTime: "09:00", endTime: "10:00", useType: "individual", note: " Rövid megjegyzés ", idempotencyKey: "29000000-0000-0000-0000-000000000001" };
describe("booking form", () => {
  it("kiszűri a nem létező naptári napot", () => { expect(isValidDate("2026-02-29")).toBe(false); expect(isValidDate("2028-02-29")).toBe(true); });
  it("Budapest helyi időből helyes UTC időpontot készít", () => {
    expect(budapestLocalToIso("2026-01-10", "09:00")).toBe("2026-01-10T08:00:00.000Z");
    expect(budapestLocalToIso("2026-07-10", "09:00")).toBe("2026-07-10T07:00:00.000Z");
  });
  it("a konkrét DST-váltási napokon is helyes 09:00 helyi időt ad", () => {
    expect(budapestLocalToIso("2026-03-29", "09:00")).toBe("2026-03-29T07:00:00.000Z");
    expect(budapestLocalToIso("2026-10-25", "09:00")).toBe("2026-10-25T08:00:00.000Z");
  });
  it("érvényes foglalást RPC-paraméterré alakít", () => expect(parseBookingForm(valid)).toEqual({ ok: true, value: { roomId: valid.roomId, date: valid.date, startAt: "2026-09-10T07:00:00.000Z", endAt: "2026-09-10T08:00:00.000Z", useType: "individual", note: "Rövid megjegyzés", idempotencyKey: valid.idempotencyKey } }));
  it("fail-closed módon elutasítja a hibás UUID-t és időrácsot", () => { expect(parseBookingForm({ ...valid, roomId: "nem-uuid" }).ok).toBe(false); expect(parseBookingForm({ ...valid, startTime: "09:15" }).ok).toBe(false); });
  it("elutasítja a rövid és nyitvatartáson kívüli időt", () => {
    expect(parseBookingForm({ ...valid, endTime: "09:30" })).toMatchObject({ ok: false, error: "A foglalás legalább 60 perces legyen." });
    expect(parseBookingForm({ ...valid, startTime: "06:30", endTime: "07:30" })).toMatchObject({ ok: false, error: "A foglalásnak 07:00 és 22:00 közé kell esnie." });
  });
  it("pontos üzenettel utasítja el a kezdés előtti vagy azonos befejezést", () => {
    expect(parseBookingForm({ ...valid, startTime: "10:00", endTime: "09:00" })).toMatchObject({ ok: false, error: "A befejezésnek a kezdés után kell lennie." });
    expect(parseBookingForm({ ...valid, endTime: "09:00" })).toMatchObject({ ok: false, error: "A befejezésnek a kezdés után kell lennie." });
  });
});
