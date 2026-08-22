import { describe, expect, it } from "vitest";
import { oneHourAfter } from "./booking-time";

describe("oneHourAfter", () => {
  it("a kezdés módosításakor egy órával későbbi befejezést ad", () => {
    expect(oneHourAfter("13:00")).toBe("14:00");
    expect(oneHourAfter("13:30")).toBe("14:30");
  });

  it("a zárási időnél nem ad későbbi értéket", () => {
    expect(oneHourAfter("21:00")).toBe("22:00");
  });

  it("hibás értéket változtatás nélkül ad vissza", () => {
    expect(oneHourAfter("hibás")).toBe("hibás");
  });
});
