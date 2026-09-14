import { NextResponse } from "next/server";

import { requireAdmin } from "@/lib/auth";

export const runtime = "nodejs";

export async function POST() {
  await requireAdmin();
  return NextResponse.json({
    error: "A Papp Dalma próbaimport lezárult. Használd az ügyfelenkénti Migráció folyamatot.",
  }, { status: 410, headers: { "Cache-Control": "no-store" } });
}
