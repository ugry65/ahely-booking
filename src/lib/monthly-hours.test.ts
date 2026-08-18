import { describe, expect, it } from "vitest";
import { csvCell, monthStart, monthlyHoursCsv, validMonth } from "./monthly-hours";

describe("monthly hours export", () => {
  it("csak érvényes YYYY-MM hónapot fogad el", () => {
    expect(validMonth("2026-08")).toBe(true);
    expect(monthStart("2026-08")).toBe("2026-08-01");
    expect(validMonth("2026-13")).toBe(false);
    expect(monthStart("2026-8")).toBeNull();
  });
  it("idézőjelet és pontosvesszőt biztonságosan exportál", () => {
    expect(csvCell('Nagy; "Anna"')).toBe('"Nagy; ""Anna"""');
  });
  it("képlet-injection gyanús értéket aposztróffal semlegesít", () => {
    expect(csvCell("=1+1")).toBe("\"'=1+1\"");
    expect(csvCell("  -2+3")).toBe("\"'  -2+3\"");
  });
  it("BOM-mal és stabil oszlopsorrenddel készít CSV-t", () => {
    const csv = monthlyHoursCsv("2026-08", [{ user_id: "id", user_name: "Teszt User", email: "teszt@example.invalid", booking_count: 2, total_minutes: 150, total_hours: "2.50" }]);
    expect(csv.startsWith("\uFEFF\"Hónap\";\"Felhasználó\"")).toBe(true);
    expect(csv).toContain('"2026-08";"Teszt User";"teszt@example.invalid";"2";"150";"2.50"');
  });
});
