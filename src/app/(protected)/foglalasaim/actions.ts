"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireActiveProfile } from "@/lib/auth";
import { parseCancelBookingForm, parseUpdateBookingForm } from "@/lib/booking-operation-form";
import { createClient } from "@/lib/supabase/server";

function safeReturnTo(formData: FormData) {
  const candidate = String(formData.get("returnTo") ?? "");
  if (!candidate.startsWith("/foglalasaim")) return "/foglalasaim";
  try {
    const url = new URL(candidate, "https://ahely.local");
    if (url.pathname !== "/foglalasaim") return "/foglalasaim";
    const params = new URLSearchParams();
    const view = url.searchParams.get("view");
    const date = url.searchParams.get("date");
    if (view && ["day", "month", "list"].includes(view)) params.set("view", view);
    if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) params.set("date", date);
    const query = params.toString();
    return query ? `/foglalasaim?${query}` : "/foglalasaim";
  } catch {
    return "/foglalasaim";
  }
}

function resultUrl(formData: FormData, kind: "hiba" | "uzenet", message: string) {
  const url = new URL(safeReturnTo(formData), "https://ahely.local");
  url.searchParams.set(kind, message);
  return `${url.pathname}?${url.searchParams.toString()}`;
}

function safeRpcMessage(error: { code?: string; message: string }, fallback: string) {
  return error.code === "P0001" && error.message.length <= 240 ? error.message : fallback;
}

export async function updateOwnBooking(formData: FormData) {
  await requireActiveProfile();
  const input = Object.fromEntries(["bookingId", "expectedUpdatedAt", "roomId", "date", "startTime", "endTime", "useType", "note", "bookingTitle", "idempotencyKey"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseUpdateBookingForm(input);
  if (!parsed.ok) redirect(resultUrl(formData, "hiba", parsed.error));
  const value = parsed.value;
  const supabase = await createClient();
  const { error } = await supabase.rpc("update_booking", {
    p_booking_id: value.bookingId, p_expected_updated_at: value.expectedUpdatedAt,
    p_room_id: value.roomId, p_start_at: value.startAt, p_end_at: value.endAt,
    p_use_type: value.useType, p_note: value.note, p_idempotency_key: value.idempotencyKey,
    p_booking_title: value.bookingTitle,
  });
  if (error) redirect(resultUrl(formData, "hiba", safeRpcMessage(error, "A foglalás módosítása nem sikerült. Kérlek, töltsd újra az oldalt és próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  redirect(resultUrl(formData, "uzenet", "A foglalás módosítása sikerült."));
}

export async function cancelOwnBooking(formData: FormData) {
  await requireActiveProfile();
  const input = Object.fromEntries(["bookingId", "reason", "idempotencyKey"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseCancelBookingForm(input);
  if (!parsed.ok) redirect(resultUrl(formData, "hiba", parsed.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_booking", {
    p_booking_id: parsed.value.bookingId, p_reason: parsed.value.reason,
    p_idempotency_key: parsed.value.idempotencyKey,
  });
  if (error) redirect(resultUrl(formData, "hiba", safeRpcMessage(error, "A foglalás lemondása nem sikerült. Kérlek, töltsd újra az oldalt és próbáld újra.")));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  redirect(resultUrl(formData, "uzenet", "A foglalást sikeresen lemondtad."));
}
