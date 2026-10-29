import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createClient: vi.fn(),
  updateUser: vi.fn(),
  redirect: vi.fn((url: string): never => { throw new Error(url); }),
}));

vi.mock("next/navigation", () => ({ redirect: mocks.redirect }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { updatePassword } from "./actions";

describe("password update feedback", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.createClient.mockResolvedValue({ auth: {
      getClaims: vi.fn().mockResolvedValue({ data: null }),
      updateUser: mocks.updateUser,
    } });
  });

  async function submit(error: { code?: string; message?: string } | null) {
    mocks.updateUser.mockResolvedValue({ error });
    const form = new FormData();
    form.set("password", "TestOnlyPassword42");
    await expect(updatePassword(form)).rejects.toThrow();
    expect(mocks.updateUser).toHaveBeenCalledExactlyOnceWith({ password: "TestOnlyPassword42" });
    return new URL(mocks.redirect.mock.calls[0][0], "https://example.invalid");
  }

  it("explains that the new password must differ when Auth returns same_password", async () => {
    const url = await submit({ code: "same_password" });
    expect(url.pathname).toBe("/jelszo-visszaallitas");
    expect(url.searchParams.get("hiba")).toBe("Az új jelszó nem egyezhet meg a jelenlegi jelszavaddal. Adj meg másik jelszót.");
  });

  it.each([{ code: "weak_password" }, { message: "same_password internal details" }])(
    "keeps other errors generic without exposing raw Auth messages: %j", async (error) => {
      const url = await submit(error);
      expect(url.pathname).toBe("/jelszo-visszaallitas");
      expect(url.searchParams.get("hiba")).toBe("A jelszó módosítása nem sikerült.");
      expect(url.href).not.toContain("TestOnlyPassword42");
    },
  );

  it("preserves successful password-update feedback", async () => {
    const url = await submit(null);
    expect(url.pathname).toBe("/belepes");
    expect(url.searchParams.get("uzenet")).toBe("A jelszó frissült, most már bejelentkezhetsz.");
    expect(url.searchParams.has("hiba")).toBe(false);
  });
});
