type DeploymentIdentity = {
  VERCEL?: string;
  VERCEL_ENV?: string;
  VERCEL_PROJECT_ID?: string;
  VERCEL_GIT_COMMIT_REF?: string;
  NEXT_PUBLIC_SUPABASE_URL?: string;
  SITE_URL?: string;
};

const targets = {
  prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo: {
    ref: "production",
    supabase: "https://yasrmxwjojepessivhmc.supabase.co",
    site: "https://foglalas.a-hely.com",
  },
  prj_LzVgZgZBCAj4zA64YoYED3XkLGKW: {
    ref: "main",
    supabase: "https://fvwapntzhavhgazeflri.supabase.co",
    site: "https://ahely-booking-staging-web.vercel.app",
  },
} as const;

export function assertVercelDeploymentIdentity(env: DeploymentIdentity) {
  if (!env.VERCEL && !env.VERCEL_ENV) return;
  if (env.VERCEL_ENV === "preview" || env.VERCEL_ENV === "development") return;
  if (env.VERCEL_ENV !== "production") {
    throw new Error("Refusing Vercel build: missing or unknown target environment");
  }
  const target = targets[env.VERCEL_PROJECT_ID as keyof typeof targets];
  if (!target || env.VERCEL_GIT_COMMIT_REF !== target.ref ||
      env.NEXT_PUBLIC_SUPABASE_URL !== target.supabase ||
      env.SITE_URL !== target.site) {
    throw new Error("Refusing Vercel production build: project, branch, Supabase or site identity mismatch");
  }
}
