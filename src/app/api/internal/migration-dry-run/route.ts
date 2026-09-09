import { NextResponse } from "next/server";

import { requireAdmin } from "@/lib/auth";
import { buildAllBookedDryRun } from "@/lib/allbooked-migration";

export const runtime = "nodejs";

const ROOM_MAPPING: Record<string, string> = {
  "Tréningterem": "Tréningterem",
  "1.Szoba-családi": "1.Szoba-családi",
  "2.Szoba": "2.Szoba",
  "3.Szoba": "3.Szoba",
  "4.Szoba": "4.Szoba",
  "5.Szoba": "5.Szoba",
  "6.Szoba": "6.Szoba",
  "Gyerek szoba": "Gyerek szoba",
  "Pitypang szoba": "Pitypang szoba",
  "Csoport szoba": "Csoport szoba",
  "Forrás tér": "Forrás tér",
};

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

  const result = buildAllBookedDryRun(await file.text(), ROOM_MAPPING);
  return NextResponse.json(result, {
    status: result.valid ? 200 : 422,
    headers: { "Cache-Control": "no-store" },
  });
}
