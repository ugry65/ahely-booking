import { describe, expect, it } from "vitest";
import { cancellationPeriod, leadTimeLabel } from "./cancellation-report";

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
});
