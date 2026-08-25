"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

function uuid(value: FormDataEntryValue | null) {
  const text = String(value ?? "");
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text) ? text : null;
}
function safeRpcMessage(error: { code?: string; message?: string } | null, fallback: string) {
  if (!error) return fallback;
  return ["P0001", "22023", "22004", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 240 ? error.message! : fallback;
}
function back(kind: "hiba" | "uzenet", message: string, month: string): never {
  const params = new URLSearchParams({ [kind]: message, honap: month });
  redirect(`/admin/befizetesek?${params.toString()}`);
}

export async function recordPayment(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  const month = String(formData.get("month") ?? "");
  const amount = Number(formData.get("amountHuf"));
  const paidOn = String(formData.get("paidOn") ?? "");
  const method = String(formData.get("method") ?? "");
  const destination = String(formData.get("destination") ?? "");
  const adminNote = String(formData.get("adminNote") ?? "").trim();

  if (!userId) back("hiba", "Érvénytelen felhasználó.", month);
  if (!/^\d{4}-\d{2}$/.test(month)) back("hiba", "Érvénytelen elszámolási hónap.", month);
  if (!Number.isSafeInteger(amount) || amount <= 0) back("hiba", "A befizetés összege pozitív egész Ft legyen.", month);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(paidOn)) back("hiba", "Érvénytelen befizetési dátum.", month);
  if (!(["cash", "bank_transfer"] as const).includes(method as "cash" | "bank_transfer")) back("hiba", "Érvénytelen fizetési mód.", month);
  if (!(["private_otp", "teem_otp", "cash_register"] as const).includes(destination as "private_otp" | "teem_otp" | "cash_register")) back("hiba", "Érvénytelen pénz célhely.", month);

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_record_payment", {
    p_user_id: userId,
    p_settlement_month: `${month}-01`,
    p_amount_huf: amount,
    p_paid_on: paidOn,
    p_method: method,
    p_destination: destination,
    p_admin_note: adminNote || null,
    p_idempotency_key: randomUUID(),
  });
  if (error) back("hiba", safeRpcMessage(error, "A befizetés rögzítése nem sikerült."), month);
  back("uzenet", "A befizetés rögzítve.", month);
}
