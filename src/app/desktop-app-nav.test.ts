import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("desktop app navigation spacing", () => {
  it("loads the dedicated desktop navigation stylesheet", () => {
    const layout = fs.readFileSync(path.join(process.cwd(), "src", "app", "layout.tsx"), "utf8");
    expect(layout).toContain('import "./desktop-app-nav.css"');
  });

  it("keeps the desktop nav aligned with the calendar header without touching mobile", () => {
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "desktop-app-nav.css"), "utf8");
    expect(css).toContain("@media (min-width: 52.01rem)");
    expect(css).toContain(".desktop-app-nav");
    expect(css).toContain("margin-inline: clamp(.75rem, 2vw, 2rem)");
  });
});
