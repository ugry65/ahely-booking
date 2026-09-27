import { describe, expect, it } from "vitest";
import { isValidPassword } from "../../lib/password-policy";

describe("password policy", () => {
  it.each(["Abcdefg1", "Jelszo12", "aB3xxxxx"])("accepts valid passwords: %s", (password) => {
    expect(isValidPassword(password)).toBe(true);
  });

  it.each(["Abcdef1", "abcdefgh1", "ABCDEFGH1", "Abcdefgh"])("rejects passwords that miss a requirement: %s", (password) => {
    expect(isValidPassword(password)).toBe(false);
  });
});
