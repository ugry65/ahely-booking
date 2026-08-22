import { describe, expect, it } from "vitest";
import { csvCell, decimalComma, monthStart, monthlyHoursCsv, validMonth } from "./monthly-hours";

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
  it("magyar decimális vesszővel adja ki az órát, hogy Excel ne dátumként értelmezze", () => {
    expect(decimalComma("4.50")).toBe("4,50");
    expect(decimalComma(24)).toBe("24,00");
  });
  it("a CSV csak a felhasználó nevét és az összes órát tartalmazza", () => {
    const csv = monthlyHoursCsv([{ user_id: "id", user_name: "Teszt User", email: "teszt@example.invalid", booking_count: 2, total_minutes: 270, total_hours: "4.50" }]);
    expect(csv.startsWith("\uFEFF\"Felhasználó\";\"Összes óra\"")).toBe(true);
    expect(csv).toContain('"Teszt User";4,50');
    expect(csv).not.toContain("E-mail");
    expect(csv).not.toContain("Foglalások száma");
  });
});
