import { NextResponse } from "next/server";

import { requireAdmin } from "@/lib/auth";
import {
  ALLBOOKED_ROOM_MAPPING,
  buildAllBookedDryRun,
  customerImportConfirmation,
  validateAllBookedCustomerImport,
} from "@/lib/allbooked-migration";
import { generateTemporaryPassword } from "@/lib/admin-user-invite";
import { isProductionMigrationTarget } from "@/lib/production-migration-target";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

type BookingUseType = "individual" | "group";

function assertProductionTarget() {
  if (!isProductionMigrationTarget({
    supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    vercelEnvironment: process.env.VERCEL_ENV,
    gitCommitRef: process.env.VERCEL_GIT_COMMIT_REF,
  })) {
    throw new Error("Az író AllBooked import kizárólag a main branch production Supabase projektjén engedélyezett.");
  }
}

function safeImportError(error: { code?: string; message?: string } | null) {
  if (error && ["P0001", "22023", "22004", "42501", "23P01"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 300) {
    return error.message!;
  }
  return "Az import tranzakció meghiúsult; adatbázis-változás nem maradt vissza.";
}

function parseTrainingUseTypes(value: FormDataEntryValue | null) {
  try {
    const parsed = JSON.parse(String(value ?? "{}")) as Record<string, unknown>;
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") return null;
    const result: Record<string, BookingUseType> = {};
    for (const [fingerprint, useType] of Object.entries(parsed)) {
      if (!/^[0-9a-f]{64}$/.test(fingerprint) || (useType !== "individual" && useType !== "group")) return null;
      result[fingerprint] = useType;
    }
    return result;
  } catch {
    return null;
  }
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
  if (!(file instanceof File) || !file.size) {
    return NextResponse.json({ error: "Válassz egy ügyfélhez tartozó AllBooked CSV fájlt." }, { status: 400 });
  }
  if (file.size > 5_000_000) {
    return NextResponse.json({ error: "Az import CSV legfeljebb 5 MB lehet." }, { status: 413 });
  }

  const dryRun = buildAllBookedDryRun(await file.text(), ALLBOOKED_ROOM_MAPPING);
  const approved = validateAllBookedCustomerImport(dryRun);
  if (!approved.valid || !approved.user || !approved.confirmation) {
    return NextResponse.json({ error: approved.issues[0] ?? "A CSV nem alkalmas ügyfélmigrációra.", dryRun }, { status: 422 });
  }

  const confirmation = String(formData.get("confirmation") ?? "");
  if (confirmation !== customerImportConfirmation(approved.user.email, dryRun.bookings.length)) {
    return NextResponse.json({ error: "A production import megerősítő szövege nem egyezik." }, { status: 400 });
  }

  const trainingUseTypes = parseTrainingUseTypes(formData.get("trainingUseTypes"));
  if (!trainingUseTypes) {
    return NextResponse.json({ error: "A Tréningterem foglalástípus-besorolása hibás." }, { status: 400 });
  }
  const trainingFingerprints = new Set(approved.trainingBookings.map((booking) => booking.sourceFingerprint));
  if (Object.keys(trainingUseTypes).some((fingerprint) => !trainingFingerprints.has(fingerprint))
      || approved.trainingBookings.some((booking) => !trainingUseTypes[booking.sourceFingerprint])) {
    return NextResponse.json({ error: "Minden Tréningterem-foglalást egyéni vagy csoportos típusba kell sorolni." }, { status: 400 });
  }

  const admin = createAdminClient();
  const { data: existingProfile, error: profileError } = await admin
    .from("profiles")
    .select("id,email")
    .eq("email", approved.user.email)
    .maybeSingle<{ id: string; email: string }>();
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
    const { data, error } = await admin.auth.admin.createUser({
      email: approved.user.email,
      password: generateTemporaryPassword(),
      email_confirm: true,
      user_metadata: {
        first_name: approved.user.firstName,
        last_name: approved.user.lastName,
        must_change_password: true,
      },
    });
    if (error || !data.user) {
      return NextResponse.json({ error: "A production Auth-felhasználó létrehozása nem sikerült." }, { status: 500 });
    }
    userId = data.user.id;
    authCreated = true;
  }

  const payload = dryRun.bookings.map((booking) => ({
    sourceFingerprint: booking.sourceFingerprint,
    roomName: booking.roomTarget,
    startLocal: booking.startLocal,
    endLocal: booking.endLocal,
    durationMinutes: booking.durationMinutes,
    bookingTitle: booking.bookingTitle,
    note: booking.note,
    useType: booking.roomTarget === "Tréningterem" ? trainingUseTypes[booking.sourceFingerprint] : "individual",
  }));
  const { data: reconciliation, error: importError } = await admin.rpc("admin_import_allbooked_customer", {
    p_actor_id: actor.id,
    p_user_id: userId,
    p_email: approved.user.email,
    p_first_name: approved.user.firstName,
    p_last_name: approved.user.lastName,
    p_phone: approved.user.phone,
    p_access_group_names: approved.requiredAccessGroups,
    p_bookings: payload,
    p_correlation_id: crypto.randomUUID(),
  });

  if (importError) {
    if (authCreated) {
      const { data: rolledBack, error: rollbackError } = await admin.rpc("admin_rollback_empty_allbooked_profile", {
        p_actor_id: actor.id,
        p_user_id: userId,
        p_email: approved.user.email,
      });
      if (!rollbackError && rolledBack === true) {
        const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
        if (deleteError) {
          console.error("AllBooked Auth compensation failed", { userId, code: deleteError.code ?? null });
          return NextResponse.json({
            error: "Az import meghiúsult, és az új Auth-fiók automatikus törlése nem sikerült. Az importot állítsd le; kézi adminisztrátori takarítás szükséges.",
            requiresManualCleanup: true,
            orphanedUserId: userId,
          }, { status: 500 });
        }
      } else {
        console.error("AllBooked profile compensation failed", { userId, code: rollbackError?.code ?? null });
        return NextResponse.json({
          error: "Az import meghiúsult, és az új profil automatikus visszavonása nem sikerült. Az importot állítsd le; kézi adminisztrátori takarítás szükséges.",
          requiresManualCleanup: true,
          orphanedUserId: userId,
        }, { status: 500 });
      }
    }
    return NextResponse.json({ error: safeImportError(importError) }, { status: 409 });
  }

  return NextResponse.json({ valid: true, reconciliation }, {
    status: 200,
    headers: { "Cache-Control": "no-store" },
  });
}
