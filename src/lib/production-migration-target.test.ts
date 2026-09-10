import { describe, expect, it } from "vitest";

import { isProductionMigrationTarget } from "./production-migration-target";

const productionTarget = {
  supabaseUrl: "https://yasrmxwjojepessivhmc.supabase.co",
  vercelEnvironment: "production",
  gitCommitRef: "main",
};

describe("isProductionMigrationTarget", () => {
  it("allows only the main production deployment with the production Supabase host", () => {
    expect(isProductionMigrationTarget(productionTarget)).toBe(true);
  });

  it.each([
    { ...productionTarget, gitCommitRef: "staging" },
    { ...productionTarget, vercelEnvironment: "preview" },
    { ...productionTarget, supabaseUrl: "https://fvwapntzhavhgazeflri.supabase.co" },
    { ...productionTarget, gitCommitRef: undefined },
    { ...productionTarget, vercelEnvironment: undefined },
    { ...productionTarget, supabaseUrl: "not-a-url" },
  ])("rejects every non-production target: %o", (target) => {
    expect(isProductionMigrationTarget(target)).toBe(false);
  });
});
