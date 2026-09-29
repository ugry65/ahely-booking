import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

describe("admin havi elszámolás snapshot-integráció", () => {
  const page = read("../app/(protected)/admin/havi-orak/page.tsx");
  const summaryExport = read("../app/(protected)/admin/havi-orak/export/route.ts");
  const detailExport = read("../app/(protected)/admin/havi-orak/reszletek-export/route.ts");
  const xlsxExport = read("../app/(protected)/admin/havi-orak/xlsx-export/route.ts");
  const actions = read("../app/(protected)/admin/havi-orak/actions.ts");
  const userPage = read("../app/(protected)/foglalasaim/page.tsx");
  const migration = read("../../supabase/migrations/20260929155816_monthly_settlement_publication.sql");

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

  it("az admin havi lezárás előtt szerveroldali összesítést és kétlépcsős megerősítést mutat", () => {
    expect(page).toContain('rpc("admin_monthly_settlement_close_preview"');
    expect(page).toContain("CloseMonthControl");
    expect(read("../app/(protected)/admin/havi-orak/close-month-control.tsx")).toContain("Lezárás megerősítése");
    expect(actions).toContain('rpc("admin_close_monthly_settlement_period"');
  });

  it("a Foglalásaim kizárólag saját publikált snapshotot olvas", () => {
    expect(userPage).toContain('rpc("list_my_latest_closed_monthly_settlement")');
    expect(migration).toContain("where ms.user_id = v_actor and ms.is_closed");
    expect(migration).toContain("revoke all on table public.settlement_revisions from public, anon, authenticated");
  });

  it("a lezárás atomikus, cutoffhoz kötött, és a korrekció a zárt revision pointerét lépteti", () => {
    expect(migration).toContain("monthly_settlement_cutoff_blockers(v_month, v_now)");
    expect(migration).toContain("monthly_settlement_periods_immutable");
    expect(migration).toContain("closed_revision_id = v_revision_id");
    expect(migration).toContain("monthly_settlement.corrected");
  });
});
