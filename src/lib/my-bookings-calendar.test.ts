import { describe, expect, it } from "vitest";
import {
  addDays,
  budapestDateFromIso,
  groupBookingsByBudapestDate,
  isValidCivilDate,
  monthGrid,
  shiftMonth,
} from "./my-bookings-calendar";

describe("my bookings calendar helpers", () => {
  it("converts ISO timestamps to the Budapest civil date", () => {
    expect(budapestDateFromIso("2026-08-22T22:30:00.000Z")).toBe("2026-08-23");
  });

  it("handles day changes across year and leap-day boundaries", () => {
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2027-01-01", -1)).toBe("2026-12-31");
    expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
    expect(addDays("2028-02-29", 1)).toBe("2028-03-01");
  });

  it("clamps month navigation to valid target dates", () => {
    expect(shiftMonth("2026-01-31", 1)).toBe("2026-02-28");
    expect(shiftMonth("2028-01-31", 1)).toBe("2028-02-29");
    expect(shiftMonth("2026-12-15", 1)).toBe("2027-01-15");
    expect(shiftMonth("2027-01-15", -1)).toBe("2026-12-15");
  });

  it("builds a Monday-first six-week month grid", () => {
    const grid = monthGrid("2026-09-15");
    expect(grid).toHaveLength(42);
    expect(grid[0]).toBe("2026-08-31");
    expect(grid[41]).toBe("2026-10-11");
  });

  it("validates civil dates strictly", () => {
    expect(isValidCivilDate("2026-02-28")).toBe(true);
    expect(isValidCivilDate("2026-02-29")).toBe(false);
    expect(isValidCivilDate("2028-02-29")).toBe(true);
  });

  it("does not shift the civil day incorrectly around DST transitions", () => {
    expect(budapestDateFromIso("2026-03-29T00:30:00.000Z")).toBe("2026-03-29");
    expect(budapestDateFromIso("2026-03-29T22:30:00.000Z")).toBe("2026-03-30");
    expect(budapestDateFromIso("2026-10-25T00:30:00.000Z")).toBe("2026-10-25");
  });

  it("groups bookings by Budapest day and sorts them by start time", () => {
    const grouped = groupBookingsByBudapestDate([
      { booking_id: "later", start_at: "2026-09-15T13:00:00.000Z" },
      { booking_id: "next-day", start_at: "2026-09-15T22:30:00.000Z" },
      { booking_id: "earlier", start_at: "2026-09-15T07:00:00.000Z" },
    ]);
    expect(grouped["2026-09-15"].map((booking) => booking.booking_id)).toEqual(["earlier", "later"]);
    expect(grouped["2026-09-16"].map((booking) => booking.booking_id)).toEqual(["next-day"]);
  });
});
