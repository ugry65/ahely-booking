"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireActiveProfile } from "@/lib/auth";
import { parseBookingForm } from "@/lib/booking-form";
import { createClient } from "@/lib/supabase/server";
function resultUrl(date: string | null, kind: "hiba" | "uzenet", message: string) {
  const params = new URLSearchParams({ [kind]: message }); if (date) params.set("datum", date); return `/foglalasok?${params.toString()}`;
}
export async function createBooking(formData: FormData) {
  const profile = await requireActiveProfile();
  const input = Object.fromEntries(["roomId", "date", "startTime", "endTime", "useType", "note"].map((key) => [key, String(formData.get(key) ?? "")]));
  const parsed = parseBookingForm(input);
  if (!parsed.ok) redirect(resultUrl(parsed.date, "hiba", parsed.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_booking", { p_room_id: parsed.value.roomId, p_user_id: profile.id, p_start_at: parsed.value.startAt, p_end_at: parsed.value.endAt, p_use_type: parsed.value.useType, p_note: parsed.value.note, p_idempotency_key: crypto.randomUUID() });
  if (error) {
    const message = error.code === "P0001" && error.message.length <= 240 ? error.message : "A foglalás mentése nem sikerült. Kérlek, próbáld újra.";
    redirect(resultUrl(parsed.value.date, "hiba", message));
  }
  revalidatePath("/foglalasok");
  redirect(resultUrl(parsed.value.date, "uzenet", "A foglalás sikeresen létrejött."));
}
