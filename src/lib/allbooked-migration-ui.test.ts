import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

describe("AllBooked ügyfélmigráció admin UI", () => {
  it("asztali és mobil admin menüből is elérhető, a mobil menü bezárul", () => {
    const desktop = read("../app/(protected)/layout.tsx");
    const mobile = read("../app/(protected)/mobile-app-nav.tsx");
    expect(desktop).toContain('<Link href="/admin/migracio">Migráció</Link>');
    expect(mobile).toContain('<Link href="/admin/migracio" onClick={closeMenu}>Migráció</Link>');
  });

  it("az általános import megtartja a production guardot és a kompenzációt", () => {
    const route = read("../app/api/internal/production-customer-migration-import/route.ts");
    expect(route).toContain("isApprovedCustomerMigrationTarget");
    expect(route).toContain("admin_import_allbooked_customer");
    expect(route).toContain("admin_rollback_empty_allbooked_profile");
    expect(route).toContain("deleteUser(userId)");
    expect(route).toContain("requiresManualCleanup: true");
    expect(route).toContain("orphanedUserId: userId");
    expect(route).toContain("Minden Tréningterem-foglalást egyéni vagy csoportos típusba kell sorolni.");
    expect(route).toContain("note: booking.note");
    const form = read("../app/(protected)/admin/migracio/dry-run-form.tsx");
    expect(form).toContain("DRY-RUN PASS");
    expect(form).toContain("még nem történt adatbetöltés");
    expect(form).toContain("Tényleges import indítása");\n    expect(form).toContain("Import feltételei:");\n    expect(form).toContain("remainingTrainingCount");\n    expect(form).toContain("Mind egyéni");\n    expect(form).toContain("Mind csoportos");\n    expect(form).toContain("Minden feltétel teljesült. A tényleges import indítható.");
  });

  it("a migrációs felület jelzi, hogy a booking megjegyzések átkerülnek", () => {
    const form = read("../app/(protected)/admin/migracio/dry-run-form.tsx");
    expect(form).toContain("Migrált megjegyzések");
    expect(form).toContain("A foglalási megjegyzést migrálja");
  });

  it("a Papp Dalma próbaimport csak pontos production guarddal vonható vissza", () => {
    const route = read("../app/api/internal/void-papp-dalma-test-import/route.ts");
    expect(route).toContain("isProductionMigrationTarget");
    expect(route).toContain("REMOVE-PAPP-DALMA-TEST-DATA");
    expect(route).toContain("admin_void_papp_dalma_test_import");
    const retiredRoute = read("../app/api/internal/production-migration-import/route.ts");
    expect(retiredRoute).toContain("status: 410");
    expect(retiredRoute).not.toContain("admin_import_papp_dalma_allbooked");
  });
});
