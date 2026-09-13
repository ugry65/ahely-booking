import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const component = readFileSync(
  new URL("../app/(protected)/foglalasok/calendar-booking-grid.tsx", import.meta.url),
  "utf8",
);
const css = readFileSync(
  new URL("../app/(protected)/foglalasok/calendar-booking-actions.css", import.meta.url),
  "utf8",
);
const mobileNavCss = readFileSync(
  new URL("../app/skedda-mobile.css", import.meta.url),
  "utf8",
);

describe("mobile booking calendar scroll", () => {
  it("keeps the compact mobile navigation visible while scrolling", () => {
    expect(mobileNavCss).toMatch(/\.mobile-app-nav\s*\{[^}]*position: sticky;[^}]*top: 0;[^}]*z-index: 50;/);
  });

  it("keeps the mobile calendar in one touch-scroll container", () => {
    expect(css).toContain("height: calc(100dvh - 5.5rem)");
    expect(css).toContain("overflow: auto");
    expect(css).toContain("overscroll-behavior: contain");
    expect(css).toContain("touch-action: pan-x pan-y");
    expect(css).toContain("-webkit-overflow-scrolling: touch");
  });

  it("keeps the room and time headers visible while scrolling to 22:00", () => {
    expect(css).toMatch(/\.calendar-corner,\s*\.room-heading\s*\{[^}]*position: sticky;[^}]*top: 0;/);
    expect(css).toMatch(/\.time-axis\s*\{[^}]*position: sticky;[^}]*left: 0;/);
  });

  it("cancels a pending long press when native scrolling starts", () => {
    expect(component).toContain("startScrollY: number");
    expect(component).toContain("RECENT_SCROLL_GUARD_MS = 180");
    expect(component).toContain("onScroll={cancelPendingTouchGesture}");
    expect(component).toContain("Math.abs(window.scrollY - gesture.startScrollY) > 1");
    expect(component).toContain('touchAction: "pan-x pan-y"');
    expect(component).toContain("onPointerCancel={(event) => endSelection(event, true)}");
  });
});
