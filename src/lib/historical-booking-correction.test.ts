import { describe, expect, it } from "vitest";
import { isHistoricalAdminEdit } from "./historical-booking-correction";
describe("historical admin correction selection", () => {
  const now=Date.parse("2026-10-14T12:00:00Z");
  it("selects only an existing started admin booking", () => {
    expect(isHistoricalAdminEdit(true,"edit","2026-10-09T06:00:00Z",now)).toBe(true);
    expect(isHistoricalAdminEdit(true,"edit","2026-10-14T12:00:00Z",now)).toBe(true);
    expect(isHistoricalAdminEdit(true,"edit","2026-10-14T13:00:00Z",now)).toBe(false);
    expect(isHistoricalAdminEdit(false,"edit","2026-10-09T06:00:00Z",now)).toBe(false);
    expect(isHistoricalAdminEdit(true,"duplicate","2026-10-09T06:00:00Z",now)).toBe(false);
    expect(isHistoricalAdminEdit(true,"create",null,now)).toBe(false);
  });
});
