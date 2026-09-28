import { describe, expect, it } from "vitest";
import { assertVercelDeploymentIdentity } from "./vercel-deployment-identity";

const production = {
  VERCEL_ENV: "production",
  VERCEL_PROJECT_ID: "prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo",
  VERCEL_GIT_COMMIT_REF: "production",
  NEXT_PUBLIC_SUPABASE_URL: "https://yasrmxwjojepessivhmc.supabase.co",
  SITE_URL: "https://foglalas.a-hely.com",
};
const staging = {
  VERCEL_ENV: "production",
  VERCEL_PROJECT_ID: "prj_LzVgZgZBCAj4zA64YoYED3XkLGKW",
  VERCEL_GIT_COMMIT_REF: "main",
  NEXT_PUBLIC_SUPABASE_URL: "https://fvwapntzhavhgazeflri.supabase.co",
  SITE_URL: "https://ahely-booking-staging-web.vercel.app",
};

describe("Vercel production build identity", () => {
  it("accepts only the exact two production-target configurations", () => {
    expect(() => assertVercelDeploymentIdentity(production)).not.toThrow();
    expect(() => assertVercelDeploymentIdentity(staging)).not.toThrow();
    expect(() => assertVercelDeploymentIdentity({ ...staging, VERCEL_ENV: "preview" })).not.toThrow();
  });
  it("rejects staging credentials in production and production credentials in staging", () => {
    for (const env of [
      { ...production, NEXT_PUBLIC_SUPABASE_URL: staging.NEXT_PUBLIC_SUPABASE_URL },
      { ...staging, NEXT_PUBLIC_SUPABASE_URL: production.NEXT_PUBLIC_SUPABASE_URL },
      { ...production, VERCEL_PROJECT_ID: staging.VERCEL_PROJECT_ID },
      { ...staging, VERCEL_PROJECT_ID: production.VERCEL_PROJECT_ID },
      { ...production, VERCEL_GIT_COMMIT_REF: "main" },
      { ...staging, VERCEL_GIT_COMMIT_REF: "production" },
      { ...production, SITE_URL: staging.SITE_URL },
      { ...staging, SITE_URL: production.SITE_URL },
      { ...production, VERCEL_PROJECT_ID: undefined },
    ]) expect(() => assertVercelDeploymentIdentity(env)).toThrow("Refusing Vercel production build");
  });
});
