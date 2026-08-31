import { NextResponse } from "next/server";

import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

function healthResponse(databaseOk: boolean, startedAt: number) {
  const responseTimeMs = Date.now() - startedAt;
  const status = databaseOk ? "ok" : "down";

  return NextResponse.json(
    {
      status,
      checks: {
        application: "ok",
        database: databaseOk ? "ok" : "down",
      },
      responseTimeMs,
      timestamp: new Date().toISOString(),
    },
    {
      status: databaseOk ? 200 : 503,
      headers: {
        "Cache-Control": "no-store, max-age=0",
      },
    },
  );
}

export async function GET() {
  const startedAt = Date.now();

  try {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("system_health_check");

    return healthResponse(!error && data === true, startedAt);
  } catch {
    return healthResponse(false, startedAt);
  }
}
