import { describe, expect, it } from "vitest";
import { buildRecurringOccurrenceDates, recurringOccurrenceDate } from "./recurring-occurrences";

describe("recurring occurrence preview", () => {
  it("generates weekly count-based dates", () => {
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-08-24", frequency: "weekly", endMode: "count", occurrenceCount: 3 })).toEqual([
      "2026-08-24", "2026-08-31", "2026-09-07",
    ]);
  });

  it("stops on an inclusive end date", () => {
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-08-24", frequency: "daily", endMode: "date", endsOn: "2026-08-26" })).toEqual([
      "2026-08-24", "2026-08-25", "2026-08-26",
    ]);
  });

  it("matches the backend month-end clamp rule", () => {
    expect(recurringOccurrenceDate("2026-01-31", "monthly", 1)).toBe("2026-02-28");
    expect(recurringOccurrenceDate("2028-01-31", "monthly", 1)).toBe("2028-02-29");
  });

  it("rejects invalid count inputs", () => {
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-08-24", frequency: "weekly", endMode: "count", occurrenceCount: 0 })).toEqual([]);
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-08-24", frequency: "weekly", endMode: "count", occurrenceCount: 401 })).toEqual([]);
  });

  it("enforces the same 366-day cap as the booking backend", () => {
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-08-24", frequency: "weekly", endMode: "count", occurrenceCount: 53 })).toHaveLength(53);
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-08-24", frequency: "weekly", endMode: "count", occurrenceCount: 54 })).toEqual([]);
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-01-31", frequency: "monthly", endMode: "count", occurrenceCount: 13 })).toHaveLength(13);
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-01-31", frequency: "monthly", endMode: "count", occurrenceCount: 14 })).toEqual([]);
    expect(buildRecurringOccurrenceDates({ firstDate: "2026-08-24", frequency: "daily", endMode: "date", endsOn: "2027-08-26" })).toEqual([]);
  });
});
