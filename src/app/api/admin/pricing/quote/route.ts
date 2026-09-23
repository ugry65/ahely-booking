import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth";
import { budapestLocalToIso, isValidDate } from "@/lib/booking-form";
import { createClient } from "@/lib/supabase/server";

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

export async function POST(request: Request) {
  try {
    await requireAdmin();
    const body = await request.json() as Record<string, unknown>;
    const userId = String(body.userId ?? "");
    const roomId = String(body.roomId ?? "");
    const date = String(body.date ?? "");
    const startTime = String(body.startTime ?? "");
    const endTime = String(body.endTime ?? "");
    const useType = body.useType === "group" || body.useType === "individual" ? body.useType : null;
    const bookingId = UUID.test(String(body.bookingId ?? "")) ? String(body.bookingId) : null;
    const overrideText = String(body.hourlyRateOverride ?? "").trim();
    const override = overrideText === "" ? null : /^\d+$/.test(overrideText) ? Number(overrideText) : NaN;
    if (!UUID.test(userId) || !UUID.test(roomId) || !isValidDate(date) || !TIME.test(startTime) || !TIME.test(endTime) || !useType || (override !== null && (!Number.isSafeInteger(override) || override < 0))) {
      return NextResponse.json({ error: "Érvénytelen díjelőnézeti adatok." }, { status: 400 });
    }
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("admin_pricing_quote", {
      p_user_id: userId, p_room_id: roomId,
      p_start_at: budapestLocalToIso(date, startTime), p_end_at: budapestLocalToIso(date, endTime),
      p_use_type: useType, p_booking_id: bookingId, p_hourly_rate_override_huf: override,
    });
    if (error) return NextResponse.json({ error: "A díjelőnézet nem számítható ki." }, { status: 400 });
    const quote = Array.isArray(data) ? data[0] : data;
    return NextResponse.json({ quote });
  } catch {
    return NextResponse.json({ error: "Nincs jogosultság a díjelőnézethez." }, { status: 403 });
  }
}
