import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const actions = readFileSync(
  new URL("../app/(protected)/admin/felhasznalok/actions.ts", import.meta.url),
  "utf8",
);
const page = readFileSync(
  new URL("../app/(protected)/admin/felhasznalok/page.tsx", import.meta.url),
  "utf8",
);

describe("admin user password management", () => {
  it("új usernek biztonságos jelszóbeállító linket küld, nem jelszót", () => {
    expect(actions).toContain("resetPasswordForEmail");
    expect(actions).toContain("sendPasswordSetupEmail(data.user.id)");
    expect(page).toContain("A kezdőjelszó nem szerepel a levélben");
  });

  it("az admin reset linket és ideiglenes jelszót is kezelhet", () => {
    expect(page).toContain("Jelszó-visszaállító link küldése");
    expect(page).toContain("Ideiglenes jelszó mentése");
    expect(actions).toContain('supabase.rpc("admin_require_password_change"');
    expect(actions).toContain("admin.auth.admin.updateUserById");
  });

  it("nem naplózza vagy adatbázis-RPC-be továbbítja a jelszót", () => {
    expect(actions).not.toMatch(/console\.(?:log|error)\([^\n]*password\.password/);
    expect(actions).not.toMatch(/admin_require_password_change[\s\S]{0,180}password:/);
  });
});
