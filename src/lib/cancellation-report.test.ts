import { describe, expect, it } from "vitest";
import { cancellationDetailsCsv, cancellationPeriod, cancellationSummaryCsv, leadTimeLabel } from "./cancellation-report";

describe("cancellation report helpers", () => {
  it("csak az elfogadott 1/3/6/12 havi időszakot fogadja el", () => {
    expect(cancellationPeriod("1")).toBe(1);
    expect(cancellationPeriod("6")).toBe(6);
    expect(cancellationPeriod("12")).toBe(12);
    expect(cancellationPeriod("2")).toBe(3);
    expect(cancellationPeriod(undefined)).toBe(3);
  });

  it("emberileg olvashatóvá teszi a kezdés előtti időt", () => {
    expect(leadTimeLabel(90)).toBe("1 óra 30 perc");
    expect(leadTimeLabel(2940)).toBe("2 nap 1 óra");
    expect(leadTimeLabel(25)).toBe("25 perc");
  });

  it("az összesítő CSV tartalmazza a saját lemondási arányt és Excel-biztos órát", () => {
    const csv = cancellationSummaryCsv([{ user_id: "u", user_name: "Teszt User", total_bookings: 20, cancelled_count: 5, cancelled_hours: "6.50", user_cancelled_count: 4, user_cancelled_hours: "5.50", cancellation_rate: "20.0" }]);
    expect(csv).toContain("Lemondási arány %");
    expect(csv).toContain("Teszt User");
    expect(csv).toContain("6,50");
    expect(csv).toContain("20,00");
  });

  it("a részletes CSV megőrzi az eredeti foglalási és lemondási adatokat", () => {
    const csv = cancellationDetailsCsv([{ booking_id: "b", user_id: "u", user_name: "Teszt User", booking_date: "2026-08-22", room_name: "3.Szoba", start_time: "09:00:00", end_time: "10:30:00", cancelled_hours: "1.50", cancelled_at: "2026-08-20T08:00:00Z", minutes_before_start: 3000, cancellation_reason: "Betegség", cancelled_by_user: true, cancelled_by_name: "Teszt User" }]);
    expect(csv).toContain("2026-08-22");
    expect(csv).toContain("3.Szoba");
    expect(csv).toContain("1,50");
    expect(csv).toContain("Betegség");
    expect(csv).toContain("Teszt User (user)");
  });
});
