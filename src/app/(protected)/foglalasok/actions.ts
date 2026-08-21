"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireActiveProfile } from "@/lib/auth";
import { parseBookingForm } from "@/lib/booking-form";
import { parseCancelBookingForm, parseUpdateBookingForm } from "@/lib/booking-operation-form";
import { createClient } from "@/lib/supabase/server";

function resultUrl(date: string | null, kind: "hiba" | "uzenet", message: string) {
  const params = new URLSearchParams({ [kind]: message }); if (date) params.set("datum", date); return `/foglalasok?${params.toString()}`;
}
function safeRpcMessage(error: { code?: string; message: string }, fallback: string) {
  return error.code === "P0001" && error.message.length <= 260 ? error.message : fallback;
}
function parseScope(value: FormDataEntryValue | null) {
  const scope = String(value ?? "occurrence");
  return scope === "following" || scope === "series" ? scope : "occurrence";
}

export async function createBooking(formData: FormData) {
  const profile = await requireActiveProfile();
  const input = Object.fromEntries(["roomId", "date", "startTime", "endTime", "useType", "note", "idempotencyKey"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseBookingForm(input);
  if (!parsed.ok) redirect(resultUrl(parsed.date, "hiba", parsed.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_booking", { p_room_id: parsed.value.roomId, p_user_id: profile.id, p_start_at: parsed.value.startAt, p_end_at: parsed.value.endAt, p_use_type: parsed.value.useType, p_note: parsed.value.note, p_idempotency_key: parsed.value.idempotencyKey });
  if (error) redirect(resultUrl(parsed.value.date, "hiba", safeRpcMessage(error, "A foglalás mentése nem sikerült. Kérlek, próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  redirect(resultUrl(parsed.value.date, "uzenet", "A foglalás sikeresen létrejött."));
}

export async function updateCalendarBooking(formData: FormData) {
  await requireActiveProfile();
  const input = Object.fromEntries(["bookingId", "expectedUpdatedAt", "roomId", "date", "startTime", "endTime", "useType", "note", "idempotencyKey"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseUpdateBookingForm(input);
  if (!parsed.ok) redirect(resultUrl(String(formData.get("date") ?? "") || null, "hiba", parsed.error));
  const scope = parseScope(formData.get("scope"));
  const supabase = await createClient();
  const { error } = await supabase.rpc("update_booking_scope", {
    p_booking_id: parsed.value.bookingId,
    p_scope: scope,
    p_expected_updated_at: parsed.value.expectedUpdatedAt,
    p_room_id: parsed.value.roomId,
    p_start_at: parsed.value.startAt,
    p_end_at: parsed.value.endAt,
    p_use_type: parsed.value.useType,
    p_note: parsed.value.note,
    p_idempotency_key: parsed.value.idempotencyKey,
  });
  if (error) redirect(resultUrl(parsed.value.date, "hiba", safeRpcMessage(error, "A foglalás módosítása nem sikerült. Frissítsd az oldalt és próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  redirect(resultUrl(parsed.value.date, "uzenet", scope === "occurrence" ? "A foglalás módosítása sikerült." : "A sorozat érintett alkalmai módosultak."));
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
