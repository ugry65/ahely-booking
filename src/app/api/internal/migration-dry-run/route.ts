import { NextResponse } from "next/server";

import { requireAdmin } from "@/lib/auth";
import { ALLBOOKED_ROOM_MAPPING, buildAllBookedDryRun } from "@/lib/allbooked-migration";

export const runtime = "nodejs";

export async function POST(request: Request) {
  await requireAdmin();
  const formData = await request.formData();
  const file = formData.get("file");

  if (!(file instanceof File) || !file.size) {
    return NextResponse.json({ error: "Válassz AllBooked CSV fájlt." }, { status: 400 });
  }
  if (file.size > 5_000_000) {
    return NextResponse.json({ error: "A dry-run CSV legfeljebb 5 MB lehet." }, { status: 413 });
  }

  const result = buildAllBookedDryRun(await file.text(), ALLBOOKED_ROOM_MAPPING);
  return NextResponse.json(result, {
    status: result.valid ? 200 : 422,
    headers: { "Cache-Control": "no-store" },
  });
}
