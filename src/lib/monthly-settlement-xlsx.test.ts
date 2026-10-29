import { describe, expect, it } from "vitest";
import { monthlySettlementXlsx } from "./monthly-settlement-xlsx";

describe("monthly settlement XLSX export", () => {
  it.each([false, true])("az utolsó oszlop üres számlaszámmező, befizetési oszlopokkal: %s", (payments) => {
    const row = { month: "2026-10", user_id: "u", user_name: "Teszt", email: "x@example.invalid", booking_count: 1, total_minutes: 60, total_hours: 1, normal_minutes: 60, special_minutes: 0, calculated_due_huf: 2700, pricing_breakdown: [{ hourly_rate_huf: 2700 }], pricing_state: "live" as const, revision_id: null, revision_number: null };
    const raw = new TextDecoder().decode(monthlySettlementXlsx([
      { ...row, ...(payments ? { paid_huf: 1000, remaining_huf: 1700, overpaid_huf: 0, payment_status_text: "Részben fizetve" } : {}) },
    ]));
    const lastColumn = payments ? "J" : "F";
    const cells = [...raw.matchAll(/<row r="\d+">(.*?)<\/row>/g)].map((match) => [...match[1].matchAll(/<c\b/g)].length);
    expect(cells).toEqual([payments ? 10 : 6, payments ? 10 : 6, payments ? 10 : 6]);
    expect(raw).toContain(`<c r="${lastColumn}1" t="inlineStr" s="1"><is><t xml:space="preserve">Kapcsolódó számla száma</t></is></c>`);
    expect(raw).toContain(`<c r="${lastColumn}2" t="inlineStr"><is><t xml:space="preserve"></t></is></c>`);
    expect(raw).toContain(`<autoFilter ref="A1:${lastColumn}2"/>`);
    expect(raw).toContain('<c r="E2" s="3"><v>2700</v></c>');
    expect(raw).toContain('<c r="E3" s="5"><v>2700</v></c>');
  });

  it("üres exportban is tartalmazza a számlaszám fejlécet és szűrőt", () => {
    const raw = new TextDecoder().decode(monthlySettlementXlsx([]));
    expect(raw).toContain("Kapcsolódó számla száma");
    expect(raw).toContain('<autoFilter ref="A1:F1"/>');
  });

  it("valódi XLSX ZIP csomagot készít összesítő és mindösszesen sorral", () => {
    const bytes = monthlySettlementXlsx([
      { month: "2026-09", user_id: "u1", user_name: "Admin UAT", email: "admin@example.invalid", booking_count: 2, total_minutes: 1200, total_hours: "20.00", normal_minutes: 1200, special_minutes: 0, calculated_due_huf: 44000, pricing_breakdown: [{ hourly_rate_huf: 2200 }], pricing_state: "live", revision_id: null, revision_number: null },
      { month: "2026-09", user_id: "u2", user_name: "Teszt User", email: "teszt@example.invalid", booking_count: 3, total_minutes: 390, total_hours: "6.50", normal_minutes: 390, special_minutes: 0, calculated_due_huf: 17550, pricing_breakdown: [{ hourly_rate_huf: 2500 }, { hourly_rate_huf: 5000 }], pricing_state: "snapshot", revision_id: "r1", revision_number: 2 },
    ]);
    expect(Array.from(bytes.slice(0, 4))).toEqual([0x50, 0x4b, 0x03, 0x04]);
    const raw = new TextDecoder().decode(bytes);
    expect(raw).toContain("[Content_Types].xml");
    expect(raw).toContain("Elszámolási összesítés");
    expect(raw).toContain("Admin UAT");
    expect(raw).toContain("Óradíj");
    expect(raw).toContain("2 500 / 5 000 Ft");
    expect(raw).toContain("Kijelölt hónapok mindösszesen");
    expect(raw).not.toContain("Állapot");
    expect(raw).not.toContain("Revision");
    expect(raw).toContain('formatCode="#,##0 &quot;Ft&quot;"');
  });

  it("a felhasználó neve inline string, nem Excel-képlet", () => {
    const bytes = monthlySettlementXlsx([
      { month: "2026-09", user_id: "u", user_name: "=1+1", email: "x@example.invalid", booking_count: 1, total_minutes: 60, total_hours: 1, normal_minutes: 60, special_minutes: 0, calculated_due_huf: 2500, pricing_breakdown: [{ hourly_rate_huf: 2500 }], pricing_state: "live", revision_id: null, revision_number: null },
    ]);
    const raw = new TextDecoder().decode(bytes);
    expect(raw).toContain('<c r="B2" t="inlineStr"><is><t xml:space="preserve">=1+1</t></is></c>');
    expect(raw).not.toContain("<f>1+1</f>");
  });
});
