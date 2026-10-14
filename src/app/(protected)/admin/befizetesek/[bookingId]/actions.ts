"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isValidDate } from "@/lib/booking-form";

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
function returnUrl(bookingId: string, kind: string, message: string) {
  return `/admin/befizetesek/${UUID.test(bookingId) ? bookingId : "invalid"}?${new URLSearchParams({ [kind]: message })}`;
}
function errorMessage(error: { code?: string; message?: string }) {
  return ["22023", "P0001", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) < 300 ? error.message! : "A befizetési művelet nem sikerült.";
}
export async function recordBookingPayment(form: FormData) {
  await requireAdmin();
  const bookingId = String(form.get("bookingId") ?? "");
  const amountText = String(form.get("amount") ?? "");
  const amount = Number(amountText);
  const paidOn = String(form.get("paidOn") ?? "");
  const method = String(form.get("method") ?? "");
  const destination = String(form.get("destination") ?? "");
  const note = String(form.get("note") ?? "").trim();
  const key = String(form.get("idempotencyKey") ?? "");
  if (!UUID.test(bookingId) || !UUID.test(key) || !/^\d+$/.test(amountText) || !Number.isSafeInteger(amount) || amount <= 0 || amount > 100000000 || !isValidDate(paidOn) || !["cash", "bank_transfer"].includes(method) || !["cash_register", "private_otp", "teem_otp"].includes(destination) || note.length > 300) {
    redirect(returnUrl(bookingId, "hiba", "Ellenőrizd az összeget, a dátumot és a fizetési adatokat."));
  }
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_record_booking_payment", { p_booking_id: bookingId, p_amount_huf: amount, p_paid_on: paidOn, p_method: method, p_destination: destination, p_admin_note: note || null, p_idempotency_key: key });
  if (error) redirect(returnUrl(bookingId, "hiba", errorMessage(error)));
  revalidatePath("/admin/havi-orak");
  revalidatePath("/foglalasok");
  redirect(returnUrl(bookingId, "uzenet", "A befizetés rögzítve."));
}
export async function voidBookingPayment(form: FormData) {
  await requireAdmin();
  const bookingId = String(form.get("bookingId") ?? "");
  const paymentId = String(form.get("paymentId") ?? "");
  const reason = String(form.get("reason") ?? "").trim();
  if (!UUID.test(bookingId) || !UUID.test(paymentId) || !reason || reason.length > 300 || form.get("confirm") !== "yes") redirect(returnUrl(bookingId, "hiba", "A javítás indoka és megerősítése kötelező."));
  const supabase = await createClient();
  // Verify the receipt belongs to this displayed booking, not an arbitrary ID.
  const history = await supabase.rpc("admin_booking_payment_history", { p_booking_id: bookingId });
  if (history.error || !(history.data as Array<{ payment_id: string }> | null)?.some((payment) => payment.payment_id === paymentId)) redirect(returnUrl(bookingId, "hiba", "A befizetés nem található ennél a foglalásnál."));
  const { error } = await supabase.rpc("admin_void_booking_payment", { p_payment_id: paymentId, p_reason: reason });
  if (error) redirect(returnUrl(bookingId, "hiba", errorMessage(error)));
  revalidatePath("/admin/havi-orak");
  redirect(returnUrl(bookingId, "uzenet", "A téves rögzítés érvénytelenítve; a története megmaradt. Ez nem pénzvisszafizetés."));
}
