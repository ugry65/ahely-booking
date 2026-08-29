import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const globalsCss = readFileSync(new URL("../app/globals.css", import.meta.url), "utf8");
const calendarCss = readFileSync(
  new URL("../app/(protected)/foglalasok/calendar-booking-actions.css", import.meta.url),
  "utf8",
);
const pricingPage = readFileSync(
  new URL("../app/(protected)/admin/dijazas/page.tsx", import.meta.url),
  "utf8",
);

describe("protected application layout regressions", () => {
  it("a védett alkalmazást minden asztali nagyításnál a teljes viewporton tartja", () => {
    expect(globalsCss).toMatch(/main\s*\{[^}]*width:\s*100%;[^}]*min-width:\s*0;/);
    expect(globalsCss).not.toMatch(/main\s*\{[^}]*72rem/);
  });

  it("megőrzi a jóváhagyott teljes viewportos naptárszélességet", () => {
    expect(calendarCss).toMatch(/\.booking-page\s*\{[^}]*width:\s*calc\(100vw\s*-\s*\.75rem\);/);
    expect(calendarCss).toMatch(/\.booking-page\s*\{[^}]*margin-left:\s*calc\(\(100%\s*-\s*100vw\)\s*\/\s*2\s*\+\s*\.375rem\);/);
  });

  it("az érvényességi hónapot egyértelműen választható listaként jeleníti meg", () => {
    expect(pricingPage).toContain('<select name="validMonth"');
    expect(pricingPage).not.toContain('<input type="month" name="validMonth"');
    expect(pricingPage).toContain('className="pricing-editor-row"');
  });
});
