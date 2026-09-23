import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

describe("admin booking díjindok integráció", () => {
  const fields = read("../app/(protected)/foglalasok/admin-booking-pricing-fields.tsx");
  const actions = read("../app/(protected)/foglalasok/actions.ts");

  it("a meglévő indokot szerkeszthető, kontrollált mezőként továbbítja", () => {
    expect(fields).toContain('const [reason, setReason] = useState(existingReason ?? "")');
    expect(fields).toContain('name="rateOverrideReason"');
    expect(fields).toContain("value={reason}");
    expect(actions).toContain("p_override_reason: pricing.reason");
  });

  it("árváltozáskor új indokot kér, változatlan árnál a meglévőt őrzi", () => {
    expect(fields).toContain('nextRate === String(existingOverride) ? existingReason ?? "" : ""');
    expect(fields).toContain('rateChanged ? "Új módosítás indoka" : "Felülírás indoka"');
  });

  it("felülírás megszüntetésekor külön indokmezőt küld", () => {
    expect(fields).toContain('removingExisting ? "Felülírás megszüntetésének indoka"');
    expect(fields).toContain('setReason(checked ? existingReason ?? "" : "")');
  });
});
