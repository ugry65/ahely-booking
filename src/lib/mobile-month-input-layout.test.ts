import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("../app/globals.css", import.meta.url), "utf8");

describe("mobile monthly-hours layout", () => {
  it("allows fieldsets and the monthly filter grid to shrink within 390/393px viewports", () => {
    expect(css).toContain("fieldset { display: grid; min-width: 0; max-width: 100%;");
    expect(css).toContain(".monthly-filter { display: grid; min-width: 0; max-width: 100%;");
    expect(css).toContain(".monthly-filter > *, .monthly-filter label { min-width: 0; max-width: 100%; }");
    expect(css).toContain(".monthly-filter { width: 100%; grid-template-columns: minmax(0, 1fr); }");
  });

  it("constrains the native month input to the available inline width", () => {
    expect(css).toContain(
      '.monthly-filter input[type="month"] { display: block; min-width: 0; max-width: 100%; inline-size: 100%; }',
    );
  });
});
