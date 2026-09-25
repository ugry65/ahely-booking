import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";

const read = (file: string) => fs.readFileSync(path.join(__dirname, file), "utf8");

describe("migration admin layout", () => {
  it("uses page-scoped full-width cards instead of the global 30rem card limit", () => {
    const page = read("../app/(protected)/admin/migracio/page.tsx");
    const form = read("../app/(protected)/admin/migracio/dry-run-form.tsx");
    const css = read("../app/globals.css");

    expect(page).toContain('className="stack migration-page"');
    expect(form).toContain("migration-card");
    expect(css).toContain(".migration-card, .migration-import-card { width: 100%; max-width: none; }");
    expect(css).toContain(".migration-page, .migration-page > .stack { min-width: 0; width: 100%; }");
    expect(css).not.toContain("\\n");
  });
});
