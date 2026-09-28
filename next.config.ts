import type { NextConfig } from "next";
import { assertVercelDeploymentIdentity } from "./src/lib/vercel-deployment-identity";

assertVercelDeploymentIdentity({
  VERCEL_ENV: process.env.VERCEL_ENV,
  VERCEL_PROJECT_ID: process.env.VERCEL_PROJECT_ID,
  VERCEL_GIT_COMMIT_REF: process.env.VERCEL_GIT_COMMIT_REF,
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  SITE_URL: process.env.SITE_URL,
});

const nextConfig: NextConfig = {
  poweredByHeader: false,
};

export default nextConfig;
