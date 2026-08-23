import { describe, expect, it } from "vitest";

import { adminSettingsRedirectUrl } from "./admin-settings-redirect";

describe("adminSettingsRedirectUrl", () => {
  it("percent-encodes Hungarian success messages for redirect headers", () => {
    const url = adminSettingsRedirectUrl("uzenet", "Az előrefoglalási limitek elmentve.");

    expect(url).toBe("/admin/beallitasok?uzenet=Az%20el%C5%91refoglal%C3%A1si%20limitek%20elmentve.");
    expect(url).not.toMatch(/[őáéíóöőúüű]/i);
  });

  it("percent-encodes Hungarian error messages for redirect headers", () => {
    const url = adminSettingsRedirectUrl("hiba", "Csak nemnegatív egész napérték lehet.");

    expect(url).toContain("?hiba=");
    expect(url).toContain("%C3%ADv");
    expect(url).not.toMatch(/[őáéíóöőúüű]/i);
  });
});
