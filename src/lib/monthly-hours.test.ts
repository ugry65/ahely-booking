import { describe, expect, it } from "vitest";
import { appliedHourlyRatesText, csvCell, decimalComma, groupOccasionalBookingDetails, isOccasionalBookerName, occasionalBookerLabel, mergeBookingTitles, monthStart, monthlyDetailsCsv, monthlyHoursCsv, selectedMonths, validMonth } from "./monthly-hours";

describe("monthly hours export", () => {
  it("csak érvényes YYYY-MM hónapot fogad el", () => {
    expect(validMonth("2026-08")).toBe(true);
    expect(monthStart("2026-08")).toBe("2026-08-01");
    expect(validMonth("2026-13")).toBe(false);
    expect(monthStart("2026-8")).toBeNull();
  });
  it("tetszőleges több hónapot deduplikálva és rendezve fogad el", () => {
    expect(selectedMonths("2026-08,2026-06,2026-08,hibas", "2026-07")).toEqual(["2026-06", "2026-08"]);
    expect(selectedMonths(undefined, "2026-07")).toEqual(["2026-07"]);
  });
  it("idézőjelet és pontosvesszőt biztonságosan exportál", () => {
    expect(csvCell('Nagy; "Anna"')).toBe('"Nagy; ""Anna"""');
  });
  it("képlet-injection gyanús értéket aposztróffal semlegesít", () => {
    expect(csvCell("=1+1")).toBe("\"'=1+1\"");
    expect(csvCell("  -2+3")).toBe("\"'  -2+3\"");
  });
  it("magyar decimális vesszővel adja ki az órát, hogy Excel ne dátumként értelmezze", () => {
    expect(decimalComma("4.50")).toBe("4,50");
    expect(decimalComma(24)).toBe("24,00");
  });
  it("az összesítő CSV hónaponként külön sorban tartja az órákat", () => {
    const csv = monthlyHoursCsv([
      { month: "2026-07", user_id: "id", user_name: "Teszt User", email: "teszt@example.invalid", booking_count: 1, total_minutes: 60, total_hours: "1.00", normal_minutes: 60, special_minutes: 0, calculated_due_huf: 2500, pricing_breakdown: [{ hourly_rate_huf: 2500 }], pricing_state: "live", revision_id: null, revision_number: null },
      { month: "2026-08", user_id: "id", user_name: "Teszt User", email: "teszt@example.invalid", booking_count: 2, total_minutes: 270, total_hours: "4.50", normal_minutes: 210, special_minutes: 60, calculated_due_huf: 10250, pricing_breakdown: [{ hourly_rate_huf: 2500 }, { hourly_rate_huf: 5000 }], pricing_state: "snapshot", revision_id: "revision-id", revision_number: 2 },
    ]);
    expect(csv.startsWith("\uFEFF\"Hónap\";\"Felhasználó\";\"Összes óra\"")).toBe(true);
    expect(csv).toContain('"2026-08";"Teszt User";"4,50";"2500/5000";"3,50";"1,00";"10250";"Snapshot";"2"');
    expect(csv).not.toContain("E-mail");
    expect(csv).not.toContain("Foglalások száma");
  });
  it("az összesítő a ténylegesen alkalmazott egyedi óradíjakat mutatja, nem átlagot", () => {
    expect(appliedHourlyRatesText({ pricing_breakdown: [
      { hourly_rate_huf: 5000 }, { hourly_rate_huf: 2500 }, { hourly_rate_huf: 2500 },
    ] })).toBe("2 500 / 5 000 Ft");
  });
  it("a részletes CSV-ben hónap, dátum, helyiség és időintervallum is szerepel", () => {
    const csv = monthlyDetailsCsv([{ month: "2026-08", booking_id: "b", user_id: "u", user_name: "Teszt User", booking_date: "2026-08-22", room_name: "2.Szoba", booking_title: "Kovács Anna", start_time: "09:00:00", end_time: "10:30:00", total_minutes: 90, total_hours: "1.50", rate_source: "booking_override", hourly_rate_huf: 4300, amount_huf: 6450, pricing_state: "snapshot", revision_number: 3 }]);
    expect(csv).toContain('"2026-08";"Teszt User";"2026-08-22";"2.Szoba";"Kovács Anna";"09:00";"10:30";"1,50";"booking_override";"4300";"6450";"Snapshot";"3"');
  });
  it("booking id alapján hozzákapcsolja a foglalás címét a pricing részlethez", () => {
    expect(mergeBookingTitles(
      [{ booking_id: "b1", room_name: "2.Szoba" }, { booking_id: "b2", room_name: "3.Szoba" }],
      [{ booking_id: "b1", booking_title: "Kliens neve" }],
    )).toEqual([
      { booking_id: "b1", room_name: "2.Szoba", booking_title: "Kliens neve" },
      { booking_id: "b2", room_name: "3.Szoba", booking_title: null },
    ]);
  });
  it("felismeri a két technikai alkalmi foglalót", () => {
    expect(isOccasionalBookerName("Alkalmi Egyéni")).toBe(true);
    expect(isOccasionalBookerName("  alkalmi   csoport ")).toBe(true);
    expect(isOccasionalBookerName("Kiss Anna")).toBe(false);
    expect(isOccasionalBookerName("Csoport A.", "alkalmifoglalas@gmail.com")).toBe(true);
    expect(occasionalBookerLabel("Csoport A.", "alkalmifoglalas@gmail.com")).toBe("Alkalmi Csoport");
    expect(occasionalBookerLabel("Teszt", "ujtanacsadas2018@gmail.com")).toBe("Alkalmi Egyéni");
  });
  it("booking_title szerint összevonja az alkalmi ügyfelek óráit és összegeit", () => {
    expect(groupOccasionalBookingDetails([
      { booking_title: "Szoke kathrin", total_hours: "1.00", amount_huf: 4000 },
      { booking_title: "  Szoke   Kathrin ", total_hours: "1.50", amount_huf: 6000 },
      { booking_title: "Nagy Péter", total_hours: "2.00", amount_huf: 8000 },
    ])).toEqual([
      { customer_name: "Nagy Péter", total_hours: 2, calculated_due_huf: 8000 },
      { customer_name: "Szoke kathrin", total_hours: 2.5, calculated_due_huf: 10000 },
    ]);
  });
  it("az összesítő export az alkalmi technikai user alatt ügyfelenként is megbont", () => {
    const rows = [{
      month: "2026-09", user_id: "occasional", user_name: "Alkalmi Csoport", email: "alkalmifoglalas@gmail.com",
      booking_count: 2, total_minutes: 1800, total_hours: "30.00", normal_minutes: 0, special_minutes: 1800,
      calculated_due_huf: 150000, pricing_breakdown: [{ hourly_rate_huf: 5000 }], pricing_state: "snapshot" as const,
      revision_id: "rev", revision_number: 1,
    }];
    const details = [
      { month: "2026-09", booking_id: "b1", user_id: "occasional", user_name: "Alkalmi Csoport", booking_date: "2026-09-01", room_name: "Tréningterem", booking_title: "Szabó Julianna pilács", start_time: "08:00:00", end_time: "18:00:00", total_minutes: 600, total_hours: "10.00", rate_source: "training_room" as const, hourly_rate_huf: 5000, amount_huf: 50000, pricing_state: "snapshot" as const, revision_number: 1 },
      { month: "2026-09", booking_id: "b2", user_id: "occasional", user_name: "Alkalmi Csoport", booking_date: "2026-09-02", room_name: "Tréningterem", booking_title: "Szabó Julianna pilácsx", start_time: "08:00:00", end_time: "20:00:00", total_minutes: 1200, total_hours: "20.00", rate_source: "training_room" as const, hourly_rate_huf: 5000, amount_huf: 100000, pricing_state: "snapshot" as const, revision_number: 1 },
    ];
    const csv = monthlyHoursCsv(rows, details);
    expect(csv).toContain('"2026-09";"Alkalmi Csoport";"30,00"');
    expect(csv).toContain('"Szabó Julianna pilács"');

    expect(csv).toContain('"2026-09";"Alkalmi Csoport";"30,00"');
  });
});
