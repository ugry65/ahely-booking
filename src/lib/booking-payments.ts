export type PaymentBalance = { paid_huf: number | string; remaining_huf: number | string; overpaid_huf: number | string };
export type MonthlyPaymentBalance = PaymentBalance & { user_id: string; user_name: string; due_huf: number | string };
export type BookingPaymentTotal = { booking_id: string; paid_huf: number | string };

export function paymentBalance(due: number, paid: number): PaymentBalance {
  return { paid_huf: paid, remaining_huf: Math.max(due - paid, 0), overpaid_huf: Math.max(paid - due, 0) };
}
export function paymentLabel(balance: PaymentBalance): string {
  if (Number(balance.overpaid_huf) > 0) return "Túlfizetve";
  if (Number(balance.paid_huf) === 0) return Number(balance.remaining_huf) === 0 ? "Nincs fizetendő" : "Nincs fizetve";
  return Number(balance.remaining_huf) === 0 ? "Fizetve" : "Részben fizetve";
}
export function mergePaymentBalances<T extends { user_id: string }>(rows: T[], balances: MonthlyPaymentBalance[]) {
  const byUser = new Map(balances.map((balance) => [balance.user_id, balance]));
  return rows.map((row) => {
    const balance = byUser.get(row.user_id);
    if (!balance) throw new Error("Hiányos befizetési összesítés.");
    return { ...row, calculated_due_huf: Number(balance.due_huf), paid_huf: Number(balance.paid_huf), remaining_huf: Number(balance.remaining_huf), overpaid_huf: Number(balance.overpaid_huf), payment_status_text: paymentLabel(balance) };
  });
}
export function mergeBookingPaymentTotals<T extends { booking_id: string; amount_huf: number }>(rows: T[], totals: BookingPaymentTotal[]) {
  const byBooking = new Map(totals.map((total) => [total.booking_id, Number(total.paid_huf)]));
  return rows.map((row) => {
    const balance = paymentBalance(Number(row.amount_huf), byBooking.get(row.booking_id) ?? 0);
    return { ...row, ...balance, payment_status_text: paymentLabel(balance) };
  });
}
