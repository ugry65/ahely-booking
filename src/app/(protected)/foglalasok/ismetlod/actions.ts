"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireActiveProfile } from "@/lib/auth";
import { parseRecurringBookingForm } from "@/lib/recurring-booking-form";
import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
function resultUrl(kind: "hiba" | "sorozat", value: string) { return `/foglalasok/ismetlod?${new URLSearchParams({ [kind]: value }).toString()}`; }

export async function createRecurringBooking(formData: FormData) {
  const profile = await requireActiveProfile();
  const keys = ["roomId", "date", "startTime", "endTime", "useType", "note", "idempotencyKey", "frequency", "endMode", "endsOn", "occurrenceCount", "exceptionDates", "conflictPolicy"];
  const parsed = parseRecurringBookingForm(Object.fromEntries(keys.map((key) => [key, String(formData.get(key) ?? "")])));
  if (!parsed.ok) redirect(resultUrl("hiba", parsed.error));
  const value = parsed.value;
  const requestedTarget = String(formData.get("targetUserId") ?? "");
  const userId = profile.role === "admin" && UUID_PATTERN.test(requestedTarget) ? requestedTarget : profile.id;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_booking_series", {
    p_room_id: value.roomId, p_user_id: userId,
    p_first_start_at: value.firstStartAt, p_first_end_at: value.firstEndAt,
    p_frequency: value.frequency, p_ends_on: value.endsOn,
    p_occurrence_count: value.occurrenceCount, p_exception_dates: value.exceptionDates,
    p_conflict_policy: value.conflictPolicy, p_use_type: value.useType,
    p_note: value.note, p_idempotency_key: value.idempotencyKey,
  });
  if (error) {
    const message = error.code === "P0001" && error.message.length <= 300 ? error.message : "A foglalási sorozat létrehozása nem sikerült. Kérlek, próbáld újra.";
    redirect(resultUrl("hiba", message));
  }
  const seriesId = typeof data === "object" && data !== null && "series_id" in data ? String(data.series_id) : "";
  if (!UUID_PATTERN.test(seriesId)) redirect(resultUrl("hiba", "A sorozat létrejött, de az eredmény megjelenítése nem sikerült. Ellenőrizd a Foglalásaim oldalt."));
  revalidatePath("/foglalasok"); revalidatePath("/foglalasaim");
  redirect(resultUrl("sorozat", seriesId));
}
