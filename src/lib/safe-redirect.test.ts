import { describe, expect, it } from "vitest";

import { getSafeAuthRedirectPath } from "./safe-redirect";

describe("getSafeAuthRedirectPath", () => {
  it.each(["/foglalasok", "/jelszo-visszaallitas"])(
    "engedélyezi a rögzített belső célútvonalat: %s",
    (path) => expect(getSafeAuthRedirectPath(path)).toBe(path),
  );

  it.each([
    "//evil.example",
    "/\\evil.example",
    "/\t/evil.example",
    "https://evil.example",
    "/admin/felhasznalok",
    "",
  ])("biztonságos alapértékre cseréli a tiltott célútvonalat: %j", (path) => {
    expect(getSafeAuthRedirectPath(path)).toBe("/foglalasok");
  });

  it("null értéknél is biztonságos alapútvonalat ad", () => {
    expect(getSafeAuthRedirectPath(null)).toBe("/foglalasok");
  });
});
