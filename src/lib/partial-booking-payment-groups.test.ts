import { expect,it } from "vitest";
import { mergeBookingPaymentTotals } from "./booking-payments";
it("shows a shared group balance but never doubles exported money", () => {
  const group = { payment_group_id: "group-12345678", group_due_huf: 10000, group_paid_huf: 14000 };
  const rows = mergeBookingPaymentTotals([{ booking_id: "root", amount_huf: 4000 },{ booking_id: "child", amount_huf: 6000 }],
    [{ booking_id: "root", paid_huf: 14000, is_group_anchor: true, ...group }, { booking_id: "child", paid_huf: 0, is_group_anchor: false, ...group }]);
  expect(rows.reduce((n,r) => n+Number(r.paid_huf),0)).toBe(14000);
  expect(rows.reduce((n,r) => n+Number(r.overpaid_huf),0)).toBe(4000);
  expect(rows.reduce((n,r) => n+Number(r.remaining_huf),0)).toBe(0);
  expect(rows.every(r => r.payment_status_text.includes("Közös foglaláscsoport"))).toBe(true);
});
