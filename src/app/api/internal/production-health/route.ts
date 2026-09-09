import { NextResponse, type NextRequest } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

function isAuthorized(request: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  return request.headers.get("authorization") === `Bearer ${secret}`;
}

export async function GET(request: NextRequest) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }

  try {
    const supabase = createAdminClient();
    const { error } = await supabase.from("app_settings").select("key").limit(1);

    if (error) {
      return NextResponse.json({ ok: false }, { status: 503 });
    }

    return NextResponse.json(
      { ok: true },
      {
        status: 200,
        headers: { "Cache-Control": "no-store" },
      },
    );
  } catch {
    return NextResponse.json({ ok: false }, { status: 503 });
  }
}
