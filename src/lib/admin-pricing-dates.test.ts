import { describe, expect, it } from "vitest";
import { pricingMonthStart, pricingValidFrom } from "./admin-pricing-dates";

describe("global pricing date boundary", () => {
  it("allows October 1 on October 13 for an open month", () => {
    const month = pricingMonthStart(new Date("2026-10-13T20:54:58Z"));
    expect(pricingValidFrom(month, false)).toBe("2026-10-01");
  });
  it.each([
    ["2026-09-30T22:00:00Z", "2026-10-01"],
    ["2026-09-30T21:59:59Z", "2026-09-01"],
    ["2026-12-31T23:00:00Z", "2027-01-01"],
    ["2026-03-29T01:00:00Z", "2026-03-01"],
    ["2026-10-25T01:00:00Z", "2026-10-01"],
  ])("uses Budapest calendar at %s", (timestamp, expected) => {
    expect(pricingMonthStart(new Date(timestamp))).toBe(expected);
  });
  it("moves closed October to November and closed December to next January", () => {
    expect(pricingValidFrom("2026-10-01", true)).toBe("2026-11-01");
    expect(pricingValidFrom("2026-12-01", true)).toBe("2027-01-01");
  });
});
