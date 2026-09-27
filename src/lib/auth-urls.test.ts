import { describe, expect, it } from "vitest";
import { passwordRecoveryRedirect } from "./auth-urls";

describe("passwordRecoveryRedirect", () => {
  it("uses the canonical SITE_URL", () => {
    expect(passwordRecoveryRedirect("https://ahely-booking-staging-web.vercel.app")).toBe("https://ahely-booking-staging-web.vercel.app/auth/confirm");
  });
  it("removes a trailing slash", () => {
    expect(passwordRecoveryRedirect("https://example.com/")).toBe("https://example.com/auth/confirm");
  });
  it("fails closed when SITE_URL is missing", () => {
    expect(passwordRecoveryRedirect(undefined)).toBeNull();
  });
});
