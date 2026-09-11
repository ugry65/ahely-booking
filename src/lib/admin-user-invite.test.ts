import { describe, expect, it } from "vitest";

import {
  DUPLICATE_EMAIL_MESSAGE,
  GENERIC_AUTH_CREATE_ERROR_MESSAGE,
  authCreateErrorMessage,
  generateTemporaryPassword,
} from "./admin-user-invite";

describe("admin user invite", () => {
  it("generates a strong temporary password below the Supabase 72-character maximum", () => {
    const password = generateTemporaryPassword(() => "123e4567-e89b-42d3-a456-426614174000");

    expect(password).toHaveLength(36);
    expect(password.length).toBeLessThanOrEqual(72);
    expect(password).toMatch(/[a-z]/);
    expect(password).toMatch(/[A-Z]/);
    expect(password).toMatch(/[0-9]/);
    expect(password).toMatch(/[^a-zA-Z0-9]/);
  });

  it.each(["email_exists", "user_already_exists"])(
    "shows the duplicate message only for the %s Auth error code",
    (code) => {
      expect(authCreateErrorMessage({ code })).toBe(DUPLICATE_EMAIL_MESSAGE);
    },
  );

  it.each([
    { code: "weak_password" },
    { code: "unexpected_failure" },
    {},
    null,
  ])("uses a safe generic message for non-duplicate Auth failures", (error) => {
    expect(authCreateErrorMessage(error)).toBe(GENERIC_AUTH_CREATE_ERROR_MESSAGE);
  });
});
