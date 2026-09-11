import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("calendar header navigation regression", () => {
  it("clears pending state when the selected date changes and has a fail-safe timeout", () => {
    const source = fs.readFileSync(
      path.join(process.cwd(), "src", "app", "(protected)", "foglalasok", "calendar-date-navigation.tsx"),
      "utf8",
    );

    expect(source).toContain("}, [selectedDate]);");
    expect(source).toContain("setTimeout(() => setPendingTarget(null), 8000)");
    expect(source).toContain('pendingTarget === "previous" ? "Folyamatban…" : "←"');
    expect(source).toContain('pendingTarget === "next" ? "Folyamatban…" : "→"');
  });

  it("keeps calendar controls away from viewport edges without shrinking the grid", () => {
    const css = fs.readFileSync(
      path.join(process.cwd(), "src", "app", "(protected)", "foglalasok", "calendar-header.css"),
      "utf8",
    );

    expect(css).toContain("margin-inline: clamp(.75rem, 2vw, 2rem)");
    expect(css).toContain(".calendar-header-main");
    expect(css).toContain(".calendar-date-jump");
    expect(css).not.toContain(".calendar-grid");
  });

  it("uses the dedicated navigation component in the server page", () => {
    const page = fs.readFileSync(
      path.join(process.cwd(), "src", "app", "(protected)", "foglalasok", "page.tsx"),
      "utf8",
    );

    expect(page).toContain("CalendarDateNavigation");
    expect(page).toContain('import "./calendar-header.css"');
    expect(page).toContain('className="calendar-date-jump"');
  });
});
