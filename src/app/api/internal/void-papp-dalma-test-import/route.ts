import { NextResponse } from "next/server";

import { requireAdmin } from "@/lib/auth";
import { isProductionMigrationTarget } from "@/lib/production-migration-target";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const CONFIRMATION = "REMOVE-PAPP-DALMA-TEST-DATA";

export async function POST(request: Request) {
  const actor = await requireAdmin();
  if (!isProductionMigrationTarget({
    supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    vercelEnvironment: process.env.VERCEL_ENV,
    gitCommitRef: process.env.VERCEL_GIT_COMMIT_REF,
  })) {
    return NextResponse.json({ error: "A próbaadat-visszavonás csak a main production célon engedélyezett." }, { status: 403 });
  }
  const body = await request.json().catch(() => null) as { confirmation?: unknown } | null;
  if (body?.confirmation !== CONFIRMATION) {
    return NextResponse.json({ error: "A próbaadat-visszavonás megerősítő szövege nem egyezik." }, { status: 400 });
  }
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("admin_void_papp_dalma_test_import", {
    p_actor_id: actor.id,
    p_confirmation: CONFIRMATION,
    p_correlation_id: crypto.randomUUID(),
  });
  if (error) {
    const safe = ["P0001", "22023", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 300;
    return NextResponse.json({ error: safe ? error.message : "A próbaadatok visszavonása meghiúsult; részleges változás nem maradt vissza." }, { status: 409 });
  }
  return NextResponse.json({ valid: true, reconciliation: data }, { headers: { "Cache-Control": "no-store" } });
}
