"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireActiveProfile } from "@/lib/auth";
import { parseBookingForm } from "@/lib/booking-form";
import { parseCancelBookingForm, parseUpdateBookingForm } from "@/lib/booking-operation-form";
import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

function resultUrl(date: string | null, kind: "hiba" | "uzenet", message: string) {
  const params = new URLSearchParams({ [kind]: message }); if (date) params.set("datum", date); return `/foglalasok?${params.toString()}`;
}
function safeRpcMessage(error: { code?: string; message: string }, fallback: string) {
  return ["P0001", "22004", "22023", "42501"].includes(error.code ?? "") && error.message.length <= 260 ? error.message : fallback;
}
function pricingInput(formData: FormData) {
  const text = String(formData.get("hourlyRateOverride") ?? "").trim();
  const parsed = /^\d+$/.test(text) ? Number(text) : NaN;
  return {
    apply: String(formData.get("applyRateOverride") ?? "") === "true",
    rate: text === "" ? null : Number.isSafeInteger(parsed) ? parsed : NaN,
    reason: String(formData.get("rateOverrideReason") ?? "").trim() || null,
  };
}
function parseScope(value: FormDataEntryValue | null) {
  const scope = String(value ?? "occurrence");
  return scope === "following" || scope === "series" ? scope : "occurrence";
}
function targetUserId(profile: { id: string; role: "admin" | "user" }, formData: FormData) {
  const requested = String(formData.get("targetUserId") ?? "");
  return profile.role === "admin" && UUID_PATTERN.test(requested) ? requested : profile.id;
}

export async function createBooking(formData: FormData) {
  const profile = await requireActiveProfile();
  const input = Object.fromEntries(["roomId", "date", "startTime", "endTime", "useType", "note", "bookingTitle", "idempotencyKey"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseBookingForm(input);
  if (!parsed.ok) redirect(resultUrl(parsed.date, "hiba", parsed.error));
  const pricing = pricingInput(formData);
  if (Number.isNaN(pricing.rate)) redirect(resultUrl(parsed.value.date, "hiba", "Az egyedi óradíj csak nem negatív egész forint lehet."));
  const supabase = await createClient();
  const parameters = { p_room_id: parsed.value.roomId, p_user_id: targetUserId(profile, formData), p_start_at: parsed.value.startAt, p_end_at: parsed.value.endAt, p_use_type: parsed.value.useType, p_note: parsed.value.note, p_idempotency_key: parsed.value.idempotencyKey, p_booking_title: parsed.value.bookingTitle };
  const { error } = profile.role === "admin"
    ? await supabase.rpc("admin_create_booking_with_pricing", { ...parameters, p_hourly_rate_override_huf: pricing.rate, p_override_reason: pricing.reason })
    : await supabase.rpc("create_booking", parameters);
  if (error) redirect(resultUrl(parsed.value.date, "hiba", safeRpcMessage(error, "A foglalás mentése nem sikerült. Kérlek, próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  redirect(resultUrl(parsed.value.date, "uzenet", "A foglalás sikeresen létrejött."));
}

export async function updateCalendarBooking(formData: FormData) {
  const profile = await requireActiveProfile();
  const input = Object.fromEntries(["bookingId", "expectedUpdatedAt", "roomId", "date", "startTime", "endTime", "useType", "note", "bookingTitle", "idempotencyKey"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseUpdateBookingForm(input);
  if (!parsed.ok) redirect(resultUrl(String(formData.get("date") ?? "") || null, "hiba", parsed.error));
  const scope = parseScope(formData.get("scope"));
  const pricing = pricingInput(formData);
  if (Number.isNaN(pricing.rate)) redirect(resultUrl(parsed.value.date, "hiba", "Az egyedi óradíj csak nem negatív egész forint lehet."));
  const supabase = await createClient();
  const parameters = {
    p_booking_id: parsed.value.bookingId,
    p_scope: scope,
    p_expected_updated_at: parsed.value.expectedUpdatedAt,
    p_room_id: parsed.value.roomId,
    p_start_at: parsed.value.startAt,
    p_end_at: parsed.value.endAt,
    p_use_type: parsed.value.useType,
    p_note: parsed.value.note,
    p_idempotency_key: parsed.value.idempotencyKey,
    p_booking_title: parsed.value.bookingTitle,
  };
  const historical = profile.role === "admin" && formData.get("historicalCorrection") === "true";
  const correctionReason = String(formData.get("correctionReason") ?? "").trim();
  if (historical && (scope !== "occurrence" || !correctionReason || correctionReason.length > 300)) redirect(resultUrl(parsed.value.date, "hiba", "A múltbeli korrekcióhoz egyetlen alkalom és kötelező indok szükséges."));
  const { p_scope: historicalScope, ...singleParameters } = parameters;
  void historicalScope;
  const { error } = historical
    ? await supabase.rpc("admin_correct_open_month_booking", { ...singleParameters, p_reason: correctionReason })
    : profile.role === "admin"
    ? await supabase.rpc("admin_update_booking_scope_with_pricing", { ...parameters, p_apply_rate_override: pricing.apply, p_hourly_rate_override_huf: pricing.rate, p_override_reason: pricing.reason })
    : await supabase.rpc("update_booking_scope", parameters);
  if (error) redirect(resultUrl(parsed.value.date, "hiba", safeRpcMessage(error, "A foglalás módosítása nem sikerült. Frissítsd az oldalt és próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  revalidatePath("/admin/havi-orak");
  redirect(resultUrl(parsed.value.date, "uzenet", historical ? "A múltbeli foglalás auditált korrekciója elkészült. A havi egyenleg frissült." : scope === "occurrence" ? "A foglalás módosítása sikerült." : "A sorozat érintett alkalmai módosultak."));
}

export async function cancelCalendarBooking(formData: FormData) {
  await requireActiveProfile();
  const input = Object.fromEntries(["bookingId", "reason", "idempotencyKey"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseCancelBookingForm(input);
  const date = String(formData.get("date") ?? "") || null;
  if (!parsed.ok) redirect(resultUrl(date, "hiba", parsed.error));
  const scope = parseScope(formData.get("scope"));
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_booking_scope", {
    p_booking_id: parsed.value.bookingId,
    p_scope: scope,
    p_reason: parsed.value.reason,
    p_idempotency_key: parsed.value.idempotencyKey,
  });
  if (error) redirect(resultUrl(date, "hiba", safeRpcMessage(error, "A foglalás törlése nem sikerült. Frissítsd az oldalt és próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  redirect(resultUrl(date, "uzenet", scope === "occurrence" ? "A foglalást sikeresen törölted." : "A sorozat érintett alkalmait sikeresen törölted."));
}

export async function cancelCalendarBookingParts(formData: FormData) {
  await requireActiveProfile();
  const date = String(formData.get("date") ?? "") || null;
  const bookingId = String(formData.get("bookingId") ?? "");
  const expectedUpdatedAt = String(formData.get("expectedUpdatedAt") ?? "");
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  const raw = String(formData.get("ranges") ?? "");
  if (!UUID_PATTERN.test(bookingId) || !UUID_PATTERN.test(idempotencyKey) || !Number.isFinite(Date.parse(expectedUpdatedAt)) || reason.length > 500 || raw.length > 10000 || formData.get("confirm")!=="yes") redirect(resultUrl(date,"hiba","Érvénytelen vagy meg nem erősített lemondási kérés."));
  let ranges: unknown;
  try { ranges = JSON.parse(raw); } catch { redirect(resultUrl(date,"hiba","Érvénytelen időszak.")); }
  if (!Array.isArray(ranges) || ranges.length < 1 || ranges.length > 48 || ranges.some(r => !r || typeof r.start !== "string" || typeof r.end !== "string" || !Number.isFinite(Date.parse(r.start)) || !Number.isFinite(Date.parse(r.end)))) redirect(resultUrl(date,"hiba","Jelöld ki a lemondandó órákat."));
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_booking_parts", { p_booking_id: bookingId, p_expected_updated_at: expectedUpdatedAt, p_ranges: ranges, p_reason: reason || null, p_idempotency_key: idempotencyKey });
  if (error) redirect(resultUrl(date,"hiba",safeRpcMessage(error,"A részleges lemondás nem sikerült. Frissítsd az oldalt és próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim"); revalidatePath("/admin/havi-orak"); revalidatePath("/admin/befizetesek");
  redirect(resultUrl(date,"uzenet","A kijelölt időszakok lemondása sikerült. A többi időpont és a befizetés megmaradt."));
}
