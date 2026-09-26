import { describe, expect, it } from "vitest";
import { csvCell, decimalComma, mergeBookingTitles, monthStart, monthlyDetailsCsv, monthlyHoursCsv, selectedMonths, validMonth } from "./monthly-hours";

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
      { month: "2026-07", user_id: "id", user_name: "Teszt User", email: "teszt@example.invalid", booking_count: 1, total_minutes: 60, total_hours: "1.00", normal_minutes: 60, special_minutes: 0, calculated_due_huf: 2500, pricing_state: "live", revision_id: null, revision_number: null },
      { month: "2026-08", user_id: "id", user_name: "Teszt User", email: "teszt@example.invalid", booking_count: 2, total_minutes: 270, total_hours: "4.50", normal_minutes: 210, special_minutes: 60, calculated_due_huf: 10250, pricing_state: "snapshot", revision_id: "revision-id", revision_number: 2 },
    ]);
    expect(csv.startsWith("\uFEFF\"Hónap\";\"Felhasználó\";\"Összes óra\"")).toBe(true);
    expect(csv).toContain('"2026-08";"Teszt User";"4,50";"3,50";"1,00";"10250";"Snapshot";"2"');
    expect(csv).not.toContain("E-mail");
    expect(csv).not.toContain("Foglalások száma");
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
});
