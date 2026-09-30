import { NextResponse } from "next/server";

import { requireAdmin } from "@/lib/auth";
import {
  ALLBOOKED_ROOM_MAPPING,
  batchImportConfirmation,
  buildAllBookedDryRun,
  customerImportConfirmation,
  validateAllBookedCustomerImport,
} from "@/lib/allbooked-migration";
import { generateTemporaryPassword } from "@/lib/admin-user-invite";
import { isApprovedCustomerMigrationTarget } from "@/lib/production-migration-target";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

type BookingUseType = "individual" | "group";

function assertApprovedMigrationTarget() {
  if (!isApprovedCustomerMigrationTarget({
    supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    vercelEnvironment: process.env.VERCEL_ENV,
    gitCommitRef: process.env.VERCEL_GIT_COMMIT_REF,
  })) {
    throw new Error("Az író AllBooked import kizárólag a dedikált staging vagy production környezetben engedélyezett.");
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
    assertApprovedMigrationTarget();
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Tiltott importcél." }, { status: 403 });
  }

  const formData = await request.formData();
  const file = formData.get("file");
  if (!(file instanceof File) || !file.size) {
    return NextResponse.json({ error: "Válassz AllBooked CSV fájlt." }, { status: 400 });
  }
  if (file.size > 5_000_000) {
    return NextResponse.json({ error: "Az import CSV legfeljebb 5 MB lehet." }, { status: 413 });
  }

  const dryRun = buildAllBookedDryRun(await file.text(), ALLBOOKED_ROOM_MAPPING);
  const approved = validateAllBookedCustomerImport(dryRun);
  if (!approved.valid || !approved.confirmation) {
    return NextResponse.json({ error: approved.issues[0] ?? "A CSV nem alkalmas migrációra.", dryRun }, { status: 422 });
  }

  const expectedConfirmation = dryRun.users.length === 1
    ? customerImportConfirmation(dryRun.users[0].email, dryRun.bookings.length)
    : batchImportConfirmation(dryRun.users.length, dryRun.bookings.length);
  if (String(formData.get("confirmation") ?? "") !== expectedConfirmation) {
    return NextResponse.json({ error: "Az import megerősítő szövege nem egyezik." }, { status: 400 });
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
  const emails = dryRun.users.map((user) => user.email);
  const { data: profiles, error: profilesError } = await admin
    .from("profiles")
    .select("id,email")
    .in("email", emails);
  if (profilesError) return NextResponse.json({ error: "A célprofilok előellenőrzése nem sikerült." }, { status: 500 });

  const authByEmail = new Map<string, string>();
  for (let page = 1; page <= 100; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 });
    if (error) return NextResponse.json({ error: "Az Auth előellenőrzése nem sikerült." }, { status: 500 });
    for (const user of data.users) if (user.email) authByEmail.set(user.email.toLowerCase(), user.id);
    if (data.users.length < 100) break;
  }

  const profileByEmail = new Map((profiles ?? []).map((profile) => [profile.email.toLowerCase(), profile.id]));
  for (const user of dryRun.users) {
    const profileId = profileByEmail.get(user.email);
    const authId = authByEmail.get(user.email);
    if ((profileId && profileId !== authId) || (!profileId && authId)) {
      return NextResponse.json({ error: `${user.email}: a meglévő Auth/profile azonosság nem bizonyítható.` }, { status: 409 });
    }
  }

  const createdAuthUsers: Array<{ id: string; email: string }> = [];
  const userIds = new Map<string, string>();
  async function compensateCreatedAuth() {
    const failures: string[] = [];
    for (const created of [...createdAuthUsers].reverse()) {
      const { data: profileCleaned, error: profileCleanupError } = await admin.rpc("admin_cleanup_failed_allbooked_auth_profile", {
        p_actor_id: actor.id,
        p_user_id: created.id,
        p_expected_email: created.email,
      });
      if (profileCleanupError || profileCleaned !== true) {
        failures.push(created.id);
        continue;
      }
      const { error } = await admin.auth.admin.deleteUser(created.id);
      if (error) failures.push(created.id);
    }
    return failures;
  }

  for (const user of dryRun.users) {
    const existingId = profileByEmail.get(user.email);
    if (existingId) {
      userIds.set(user.email, existingId);
      continue;
    }
    const { data, error } = await admin.auth.admin.createUser({
      email: user.email,
      password: generateTemporaryPassword(),
      email_confirm: true,
      user_metadata: { first_name: user.firstName, last_name: user.lastName, must_change_password: true },
    });
    if (error || !data.user) {
      const failures = await compensateCreatedAuth();
      return NextResponse.json({
        error: failures.length
          ? "Az Auth-előkészítés meghiúsult, és a kompenzáló takarítás nem volt teljes. Az importot állítsd le; kézi adminisztrátori ellenőrzés szükséges."
          : "Az Auth-előkészítés meghiúsult; a létrehozott ideiglenes Auth-fiókok visszavonása megtörtént.",
        requiresManualCleanup: failures.length > 0,
      }, { status: 500 });
    }
    createdAuthUsers.push({ id: data.user.id, email: user.email });
    userIds.set(user.email, data.user.id);
  }

  const customers = approved.users.map(({ user, requiredAccessGroups }) => ({
    userId: userIds.get(user.email),
    email: user.email,
    firstName: user.firstName,
    lastName: user.lastName,
    phone: user.phone,
    accessGroupNames: requiredAccessGroups,
    bookings: dryRun.bookings.filter((booking) => booking.holderEmail === user.email).map((booking) => ({
      sourceFingerprint: booking.sourceFingerprint,
      roomName: booking.roomTarget,
      startLocal: booking.startLocal,
      endLocal: booking.endLocal,
      durationMinutes: booking.durationMinutes,
      bookingTitle: booking.bookingTitle,
      note: booking.note,
      useType: booking.roomTarget === "Tréningterem" ? trainingUseTypes[booking.sourceFingerprint] : "individual",
    })),
  }));

  const { data: reconciliation, error: importError } = await admin.rpc("admin_import_allbooked_batch", {
    p_actor_id: actor.id,
    p_customers: customers,
    p_correlation_id: crypto.randomUUID(),
  });

  if (importError) {
    const failures = await compensateCreatedAuth();
    if (failures.length) {
      console.error("AllBooked batch Auth compensation failed", { userIds: failures });
      return NextResponse.json({
        error: "Az adatbázis-import visszagördült, de néhány új Auth-fiók automatikus törlése nem sikerült. Az importot állítsd le; kézi adminisztrátori takarítás szükséges.",
        requiresManualCleanup: true,
      }, { status: 500 });
    }
    return NextResponse.json({ error: safeImportError(importError) }, { status: 409 });
  }

  return NextResponse.json({ valid: true, reconciliation }, {
    status: 200,
    headers: { "Cache-Control": "no-store" },
  });
}
