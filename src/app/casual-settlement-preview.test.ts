import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("casual settlement staging preview", () => {
  const source = fs.readFileSync(path.join(process.cwd(),"src","app","(protected)","admin","havi-orak","casual-settlement-breakdown.tsx"),"utf8");
  it("handles both casual collector users", () => {
    expect(source).toContain('"Alkalmi Csoport"');
    expect(source).toContain('"Alkalmi Egyéni"');
  });
  it("groups same booking title within month and collector", () => {
    expect(source).toContain('row.booking_title?.trim()');
    expect(source).toContain('toLocaleLowerCase("hu")');
    expect(source).toContain('group.bookings.length');
  });
  it("keeps payment checkbox non-mutating in first staging preview", () => {
    expect(source).toContain('type="checkbox" disabled');
    expect(source).toContain("pénzügyi adatot nem módosít");
  });
});
