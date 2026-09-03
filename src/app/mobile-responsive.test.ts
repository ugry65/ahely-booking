import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("mobile responsive page baseline", () => {
  it("loads the dedicated responsive layer after the existing app styles", () => {
    const layout = fs.readFileSync(path.join(process.cwd(), "src", "app", "layout.tsx"), "utf8");
    expect(layout).toContain('import "./mobile-responsive.css"');
    expect(layout.indexOf('import "./mobile-responsive.css"')).toBeGreaterThan(
      layout.indexOf('import "./mobile-hour-grid.css"'),
    );
  });

  it("prevents page-level horizontal overflow without disabling calendar inner scrolling", () => {
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "mobile-responsive.css"), "utf8");
    expect(css).toContain("overflow-x: clip");
    expect(css).toContain("main > section:not(.booking-page)");
    expect(css).toContain(".table-scroll");
    expect(css).toContain("overflow-x: auto");
    expect(css).not.toContain(".calendar-scroll {");
  });

  it("collapses desktop multi-column form and admin rows on mobile", () => {
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "mobile-responsive.css"), "utf8");
    expect(css).toContain(".pricing-editor-row");
    expect(css).toContain(".permission-matrix-row");
    expect(css).toContain(".form-row");
    expect(css).toContain("grid-template-columns: minmax(0, 1fr)");
  });

  it("loads and preserves the dedicated pricing/access mobile admin layer", () => {
    const layout = fs.readFileSync(path.join(process.cwd(), "src", "app", "layout.tsx"), "utf8");
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "mobile-admin-responsive.css"), "utf8");
    expect(layout).toContain('import "./mobile-admin-responsive.css"');
    expect(css).toContain('content: "Kliens"');
    expect(css).toContain('content: "Aktuális mód"');
    expect(css).toContain('content: "Ütemezett változások"');
    expect(css).toContain(".admin-permission-list details");
    expect(css).toContain(".permission-matrix-row > button");
  });

  it("keeps the cancellation report readable without page-level horizontal scrolling", () => {
    const page = fs.readFileSync(path.join(process.cwd(), "src", "app", "(protected)", "admin", "lemondasok", "page.tsx"), "utf8");
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "mobile-admin-responsive.css"), "utf8");
    expect(page).toContain("ResponsiveMonthField");
    expect(page).toContain("cancellation-summary-table");
    expect(page).toContain("cancellation-detail-table");
    expect(page).toContain('data-label="Lemondás ideje"');
    expect(page).toContain('data-label="Indok"');
    expect(css).toContain(".cancellation-report .table-scroll");
    expect(css).toContain("content: attr(data-label)");
  });
});
