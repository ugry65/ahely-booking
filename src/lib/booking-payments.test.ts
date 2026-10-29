import { describe, expect, it } from "vitest";
import { paymentBalance, paymentLabel, mergePaymentBalances, mergeBookingPaymentTotals } from "./booking-payments";
import { monthlyHoursCsv, type MonthlyHoursWithMonth } from "./monthly-hours";
import { monthlySettlementXlsx } from "./monthly-settlement-xlsx";

describe("booking payments", () => {
  it.each([[27000,0,"Nincs fizetve",27000,0],[27000,10000,"Részben fizetve",17000,0],[27000,27000,"Fizetve",0,0],[27000,30000,"Túlfizetve",0,3000],[0,0,"Nincs fizetendő",0,0]])("due %i paid %i", (due,paid,label,remaining,overpaid) => {
    const balance=paymentBalance(due,paid);
    expect(paymentLabel(balance)).toBe(label);
    expect(balance.remaining_huf).toBe(remaining);
    expect(balance.overpaid_huf).toBe(overpaid);
  });
  it("does not turn missing financial data into an unpaid state", () => {
    expect(() => mergePaymentBalances([{user_id:"u"}],[])).toThrow("Hiányos");
  });
  it("uses financial payable including adjustments for exported balance", () => {
    const [row]=mergePaymentBalances([{user_id:"u",calculated_due_huf:2700}],[{user_id:"u",user_name:"Test",due_huf:3000,paid_huf:1000,remaining_huf:2000,overpaid_huf:0}]);
    expect(row.calculated_due_huf).toBe(3000);
    expect(row.calculated_due_huf-Number(row.paid_huf)).toBe(row.remaining_huf);
  });
  it("matches booking totals by ID, not position or title", () => {
    const rows=mergeBookingPaymentTotals([{booking_id:"a",amount_huf:2700},{booking_id:"b",amount_huf:2700}],[{booking_id:"b",paid_huf:"1000"}]);
    expect(rows[0].payment_status_text).toBe("Nincs fizetve");
    expect(rows[1].remaining_huf).toBe(1700);
  });
  it("exports actual receipts and balance without removing gross charges", () => {
    const row: MonthlyHoursWithMonth={month:"2026-09",user_id:"u",user_name:"Test",email:"test@example.invalid",booking_count:1,total_minutes:60,total_hours:1,normal_minutes:60,special_minutes:0,calculated_due_huf:2700,pricing_breakdown:[],pricing_state:"live",revision_id:null,revision_number:null,paid_huf:1000,remaining_huf:1700,overpaid_huf:0,payment_status_text:"Részben fizetve"};
    const csv=monthlyHoursCsv([row]);
    expect(csv).toContain('"2700";"1000";"1700";"0";"Részben fizetve"');
    const xml=new TextDecoder().decode(monthlySettlementXlsx([row]));
    expect(xml).toContain("Még fizetendő");
    expect(xml).toContain("Részben fizetve");
    expect(xml).toContain('autoFilter ref="A1:J2"');
  });
});
