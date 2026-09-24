import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

describe("admin havi elszámolás snapshot-integráció", () => {
  const page = read("../app/(protected)/admin/havi-orak/page.tsx");
  const summaryExport = read("../app/(protected)/admin/havi-orak/export/route.ts");
  const detailExport = read("../app/(protected)/admin/havi-orak/reszletek-export/route.ts");
  const xlsxExport = read("../app/(protected)/admin/havi-orak/xlsx-export/route.ts");
  const actions = read("../app/(protected)/admin/havi-orak/actions.ts");

  it("a képernyő és az összesítő export ugyanazt a snapshot-aware RPC-t használja", () => {
    expect(page).toContain('rpc("admin_monthly_pricing_summary"');
    expect(summaryExport).toContain('rpc("admin_monthly_pricing_summary"');
    expect(page).not.toContain("admin_monthly_booking_hours");
    expect(summaryExport).not.toContain("admin_monthly_booking_hours");
    expect(xlsxExport).toContain('rpc("admin_monthly_pricing_summary"');
    expect(xlsxExport).not.toContain("admin_monthly_booking_hours");
    expect(page).toContain("Összesítő Excel");
  });

  it("a képernyő és a tételes export ugyanazt a snapshot-aware részletező RPC-t használja", () => {
    expect(page).toContain('rpc("admin_monthly_pricing_details"');
    expect(detailExport).toContain('rpc("admin_monthly_pricing_details"');
  });

  it("az admin felület auditált revisiont készítő tranzakcióhoz van bekötve", () => {
    expect(page).toContain("createSettlementRevision");
    expect(actions).toContain('rpc("admin_create_monthly_settlement_revision"');
    expect(actions).toContain("p_reason: reason");
    expect(actions).toContain("p_correlation_id: crypto.randomUUID()");
  });
});
