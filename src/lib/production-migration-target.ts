const PRODUCTION_PROJECT_REF = "yasrmxwjojepessivhmc";
const STAGING_PROJECT_REF = "fvwapntzhavhgazeflri";

type MigrationTarget = {
  supabaseUrl: string;
  vercelEnvironment: string | undefined;
  gitCommitRef: string | undefined;
};

function projectRefFromUrl(supabaseUrl: string) {
  try {
    const hostname = new URL(supabaseUrl).hostname;
    return hostname.endsWith(".supabase.co") ? hostname.slice(0, -".supabase.co".length) : null;
  } catch {
    return null;
  }
}

export function isProductionMigrationTarget({
  supabaseUrl,
  vercelEnvironment,
  gitCommitRef,
}: MigrationTarget) {
  return (
    projectRefFromUrl(supabaseUrl) === PRODUCTION_PROJECT_REF &&
    vercelEnvironment === "production" &&
    gitCommitRef === "main"
  );
}

export function isStagingMigrationTarget({
  supabaseUrl,
  vercelEnvironment,
  gitCommitRef,
}: MigrationTarget) {
  return (
    projectRefFromUrl(supabaseUrl) === STAGING_PROJECT_REF &&
    vercelEnvironment === "production" &&
    gitCommitRef === "main"
  );
}

export function isApprovedCustomerMigrationTarget(target: MigrationTarget) {
  return isProductionMigrationTarget(target) || isStagingMigrationTarget(target);
}
