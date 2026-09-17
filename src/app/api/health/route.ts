import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { requireEnv } from "@/lib/env";
import { runHealthCheck } from "@/lib/health";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

async function checkDatabase(): Promise<boolean> {
  const supabase = createClient(
    requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
    requireEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );

  const { data, error } = await supabase.rpc("system_health_check");
  return error === null && data === true;
}

export async function GET() {
  const result = await runHealthCheck(checkDatabase);

  return NextResponse.json(result.body, {
    status: result.status,
    headers: {
      "Cache-Control": "no-store, max-age=0",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
