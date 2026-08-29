import { describe, expect, it } from "vitest";

import { pricingMonthOptions } from "./pricing-months";

describe("pricing month options", () => {
  it("az aktuális hónaptól több évre előre választható hónapokat ad", () => {
    const options = pricingMonthOptions("2026-08");

    expect(options).toHaveLength(37);
    expect(options[0]).toEqual({ value: "2026-08", label: "2026. augusztus" });
    expect(options[2]).toEqual({ value: "2026-10", label: "2026. október" });
    expect(options.at(-1)).toEqual({ value: "2029-08", label: "2029. augusztus" });
  });

  it("hibás kezdőhónapból nem készít választási listát", () => {
    expect(pricingMonthOptions("2026-13")).toEqual([]);
    expect(pricingMonthOptions("2026-8")).toEqual([]);
  });
});
