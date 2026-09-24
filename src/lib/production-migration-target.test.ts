import { describe, expect, it } from "vitest";

import {
  isApprovedCustomerMigrationTarget,
  isProductionMigrationTarget,
  isStagingMigrationTarget,
} from "./production-migration-target";

const productionTarget = {
  supabaseUrl: "https://yasrmxwjojepessivhmc.supabase.co",
  vercelEnvironment: "production",
  gitCommitRef: "main",
};

const stagingTarget = {
  supabaseUrl: "https://fvwapntzhavhgazeflri.supabase.co",
  vercelEnvironment: "production",
  gitCommitRef: "main",
};

describe("customer migration target guard", () => {
  it("recognizes the exact production target", () => {
    expect(isProductionMigrationTarget(productionTarget)).toBe(true);
    expect(isStagingMigrationTarget(productionTarget)).toBe(false);
    expect(isApprovedCustomerMigrationTarget(productionTarget)).toBe(true);
  });

  it("recognizes the exact dedicated staging target for full migration UAT", () => {
    expect(isStagingMigrationTarget(stagingTarget)).toBe(true);
    expect(isProductionMigrationTarget(stagingTarget)).toBe(false);
    expect(isApprovedCustomerMigrationTarget(stagingTarget)).toBe(true);
  });

  it.each([
    { ...productionTarget, gitCommitRef: "staging" },
    { ...productionTarget, vercelEnvironment: "preview" },
    { ...stagingTarget, gitCommitRef: "feat/test" },
    { ...stagingTarget, vercelEnvironment: "preview" },
    { ...productionTarget, supabaseUrl: "https://unknown.supabase.co" },
    { ...productionTarget, gitCommitRef: undefined },
    { ...productionTarget, vercelEnvironment: undefined },
    { ...productionTarget, supabaseUrl: "not-a-url" },
  ])("rejects every unapproved target: %o", (target) => {
    expect(isApprovedCustomerMigrationTarget(target)).toBe(false);
  });
});
