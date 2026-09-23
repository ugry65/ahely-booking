import { describe, expect, it } from "vitest";

import { parseNonNegativeSafeIntegerHuf } from "./admin-pricing-input";

describe("admin pricing HUF input", () => {
  it("accepts exact non-negative integer amounts", () => {
    expect(parseNonNegativeSafeIntegerHuf("0")).toBe(0);
    expect(parseNonNegativeSafeIntegerHuf(" 3200 ")).toBe(3200);
    expect(parseNonNegativeSafeIntegerHuf(String(Number.MAX_SAFE_INTEGER))).toBe(Number.MAX_SAFE_INTEGER);
  });

  it("rejects values that could lose financial precision", () => {
    expect(parseNonNegativeSafeIntegerHuf("9007199254740992")).toBeNull();
    expect(parseNonNegativeSafeIntegerHuf("1.5")).toBeNull();
    expect(parseNonNegativeSafeIntegerHuf("-1")).toBeNull();
    expect(parseNonNegativeSafeIntegerHuf("")).toBeNull();
  });
});
