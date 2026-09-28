import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

describe("AllBooked ügyfélmigráció admin UI", () => {
  it("a lezárt migráció nem jelenik meg az asztali vagy mobil admin menüben", () => {
    const desktop = read("../app/(protected)/layout.tsx");
    const mobile = read("../app/(protected)/mobile-app-nav.tsx");
    expect(desktop).not.toContain('href="/admin/migracio"');
    expect(mobile).not.toContain('href="/admin/migracio"');
  });

  it("az általános import megtartja a production guardot és a kompenzációt", () => {
    const route = read("../app/api/internal/production-customer-migration-import/route.ts");
    expect(route).toContain("isApprovedCustomerMigrationTarget");
    expect(route).toContain("admin_import_allbooked_batch");
    expect(route).toContain("compensateCreatedAuth");
    expect(route).toContain("admin_cleanup_failed_allbooked_auth_profile");
    expect(route).toContain("deleteUser(created.id)");
    expect(route).toContain("requiresManualCleanup: true");
    expect(route).toContain("createdAuthUsers.push({ id: data.user.id, email: user.email })");

    const createUserIndex = route.indexOf("admin.auth.admin.createUser");
    const trackCreatedIndex = route.indexOf("createdAuthUsers.push({ id: data.user.id, email: user.email })");
    const existingUserIndex = route.indexOf("userIds.set(user.email, existingId)");
    const cleanupIndex = route.indexOf("admin_cleanup_failed_allbooked_auth_profile");
    const authDeleteIndex = route.indexOf("deleteUser(created.id)");

    expect(createUserIndex).toBeGreaterThan(-1);
    expect(trackCreatedIndex).toBeGreaterThan(createUserIndex);
    expect(existingUserIndex).toBeGreaterThan(-1);
    expect(existingUserIndex).toBeLessThan(createUserIndex);
    expect(cleanupIndex).toBeGreaterThan(-1);
    expect(authDeleteIndex).toBeGreaterThan(cleanupIndex);
    expect(route).toContain("batchImportConfirmation");
    expect(route).toContain("Minden Tréningterem-foglalást egyéni vagy csoportos típusba kell sorolni.");
    expect(route).toContain("note: booking.note");
    const form = read("../app/(protected)/admin/migracio/dry-run-form.tsx");
    expect(form).toContain("DRY-RUN PASS");
    expect(form).toContain("Egy fájl egy vagy több foglaló foglalásait is tartalmazhatja.");
    expect(form).toContain("result.importApproval.users.map");
    expect(form).toContain("még nem történt adatbetöltés");
    expect(form).toContain("Tényleges import indítása");
    expect(form).toContain("Import feltételei:");
    expect(form).toContain("remainingTrainingCount");
    expect(form).toContain("Mind egyéni");
    expect(form).toContain("Mind csoportos");
    expect(form).toContain("Minden feltétel teljesült. A tényleges import indítható.");
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
