const PRODUCTION_PROJECT_REF = "yasrmxwjojepessivhmc";

type ProductionMigrationTarget = {
  supabaseUrl: string;
  vercelEnvironment: string | undefined;
  gitCommitRef: string | undefined;
};

export function isProductionMigrationTarget({
  supabaseUrl,
  vercelEnvironment,
  gitCommitRef,
}: ProductionMigrationTarget) {
  let hostname = "";
  try {
    hostname = new URL(supabaseUrl).hostname;
  } catch {
    return false;
  }

  return (
    hostname === `${PRODUCTION_PROJECT_REF}.supabase.co` &&
    vercelEnvironment === "production" &&
    gitCommitRef === "main"
  );
}
