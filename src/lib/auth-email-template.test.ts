import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

const config = readFileSync(join(process.cwd(), "supabase/config.toml"), "utf8");
const recovery = readFileSync(join(process.cwd(), "supabase/templates/recovery.html"), "utf8");

describe("Supabase recovery e-mail sablon", () => {
  it("a magyar recovery sablont használja", () => {
    expect(config).toContain('[auth.email.template.recovery]');
    expect(config).toContain('subject = "Jelszó beállítása – A-Hely"');
    expect(config).toContain('content_path = "./supabase/templates/recovery.html"');
    expect(recovery).toContain('lang="hu"');
    expect(recovery).toContain("Jelszó beállítása vagy visszaállítása");
    expect(recovery).toContain("{{ .ConfirmationURL }}");
  });

  it("nem kér és nem közöl jelszót a levélben", () => {
    expect(recovery).not.toMatch(/kezdőjelszó|ideiglenes jelszó|jelszavad:/i);
    expect(recovery).toContain("Ha nem te kezdeményezted ezt a műveletet");
  });
});
