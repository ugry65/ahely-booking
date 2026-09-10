import { randomBytes } from "node:crypto";
import { NextResponse } from "next/server";

import { requireAdmin } from "@/lib/auth";
import {
  ALLBOOKED_ROOM_MAPPING,
  approvedBudapestLocalToIso,
  buildAllBookedDryRun,
  PAPP_DALMA_IMPORT_CONFIRMATION,
  validatePappDalmaImport,
} from "@/lib/allbooked-migration";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const PRODUCTION_PROJECT_REF = "yasrmxwjojepessivhmc";

function assertProductionTarget() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const ref = process.env.VERCEL_GIT_COMMIT_REF;
  let hostname = "";
  try { hostname = new URL(url).hostname; } catch { /* rejected below */ }
  if (hostname !== `${PRODUCTION_PROJECT_REF}.supabase.co` || (ref && ref !== "staging")) {
    throw new Error("Az író AllBooked import kizárólag a main branch production Supabase projektjén engedélyezett.");
  }
}

function safeImportError(error: { code?: string; message?: string } | null) {
  if (error && ["P0001", "22023", "22004", "42501", "23P01"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 240) {
    return error.message!;
  }
  return "Az import tranzakció meghiúsult; adatbázis-változás nem maradt vissza.";
}

export async function POST(request: Request) {
  const actor = await requireAdmin();
  try {
    assertProductionTarget();
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Tiltott importcél." }, { status: 403 });
  }

  const formData = await request.formData();
  const file = formData.get("file");
  const confirmation = String(formData.get("confirmation") ?? "");
  if (confirmation !== PAPP_DALMA_IMPORT_CONFIRMATION) {
    return NextResponse.json({ error: "A production import megerősítő szövege nem egyezik." }, { status: 400 });
  }
  if (!(file instanceof File) || !file.size) {
    return NextResponse.json({ error: "Válassz AllBooked CSV fájlt." }, { status: 400 });
  }
  if (file.size > 5_000_000) {
    return NextResponse.json({ error: "Az import CSV legfeljebb 5 MB lehet." }, { status: 413 });
  }

  const dryRun = buildAllBookedDryRun(await file.text(), ALLBOOKED_ROOM_MAPPING);
  const approved = validatePappDalmaImport(dryRun);
  if (!approved.valid || !approved.user) {
    return NextResponse.json({ error: "A CSV nem egyezik a jóváhagyott Papp Dalma 21/21 mintával.", dryRun }, { status: 422 });
  }

  const admin = createAdminClient();
  const { data: existingProfile, error: profileError } = await admin
    .from("profiles").select("id,email").eq("email", approved.user.email).maybeSingle<{ id: string; email: string }>();
  if (profileError) {
    return NextResponse.json({ error: "A célprofil előellenőrzése nem sikerült." }, { status: 500 });
  }

  let userId = existingProfile?.id ?? null;
  let authCreated = false;
  if (userId) {
    const { data, error } = await admin.auth.admin.getUserById(userId);
    if (error || data.user?.email?.toLowerCase() !== approved.user.email) {
      return NextResponse.json({ error: "A meglévő Auth/profile azonosság nem bizonyítható." }, { status: 409 });
    }
  } else {
    for (let page = 1; page <= 100; page += 1) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 });
      if (error) return NextResponse.json({ error: "Az Auth előellenőrzése nem sikerült." }, { status: 500 });
      if (data.users.some((user) => user.email?.toLowerCase() === approved.user!.email)) {
        return NextResponse.json({ error: "Az e-mail már létezik az Authban, de konzisztens profil nem található." }, { status: 409 });
      }
      if (data.users.length < 100) break;
    }
    const temporaryPassword = `${randomBytes(32).toString("base64url")}Aa1!`;
    const { data, error } = await admin.auth.admin.createUser({
      email: approved.user.email,
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: { first_name: "Dalma", last_name: "Papp", must_change_password: true },
    });
    if (error || !data.user) {
      return NextResponse.json({ error: "A production Auth-felhasználó létrehozása nem sikerült." }, { status: 500 });
    }
    userId = data.user.id;
    authCreated = true;
  }

  const payload = dryRun.bookings.map((booking) => ({
    sourceFingerprint: booking.sourceFingerprint,
    startAt: approvedBudapestLocalToIso(booking.startLocal),
    endAt: approvedBudapestLocalToIso(booking.endLocal),
    durationMinutes: booking.durationMinutes,
  }));
  const { data: reconciliation, error: importError } = await admin.rpc("admin_import_papp_dalma_allbooked", {
    p_actor_id: actor.id,
    p_user_id: userId,
    p_phone: approved.user.phone,
    p_bookings: payload,
    p_correlation_id: crypto.randomUUID(),
  });

  if (importError) {
    if (authCreated) {
      const { data: rolledBack, error: rollbackError } = await admin.rpc("admin_rollback_empty_papp_dalma_profile", {
        p_actor_id: actor.id,
        p_user_id: userId,
      });
      if (!rollbackError && rolledBack === true) {
        const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
        if (deleteError) console.error("AllBooked Auth compensation failed", { userId, code: deleteError.code ?? null });
      } else {
        console.error("AllBooked profile compensation failed", { userId, code: rollbackError?.code ?? null });
      }
    }
    return NextResponse.json({ error: safeImportError(importError) }, { status: 409 });
  }

  return NextResponse.json({ valid: true, reconciliation }, {
    status: 200,
    headers: { "Cache-Control": "no-store" },
  });
}
