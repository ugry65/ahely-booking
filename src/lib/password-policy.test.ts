import { describe, expect, it } from "vitest";

import { validateNewPassword } from "./password-policy";

describe("password policy", () => {
  it("elutasítja a rövid jelszót", () => {
    expect(validateNewPassword("short", "short")).toBe("A jelszó legalább 12 karakter legyen.");
  });
  it("elutasítja az eltérő megerősítést", () => {
    expect(validateNewPassword("legalabb-12-kar", "másik-jelszó")).toBe("A két jelszó nem egyezik.");
  });
  it("elfogadja az egyező, megfelelő hosszúságú jelszót", () => {
    expect(validateNewPassword("legalabb-12-kar", "legalabb-12-kar")).toBeNull();
  });
});
