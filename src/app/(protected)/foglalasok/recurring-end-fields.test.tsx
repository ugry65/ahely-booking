import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { RecurringEndFields } from "./recurring-end-fields";

describe("RecurringEndFields", () => {
  it("az alkalomszámos és a végdátumos lezárást is felajánlja a normál foglalási űrlaphoz", () => {
    const html = renderToStaticMarkup(<RecurringEndFields initialDate="2026-09-01" />);

    expect(html).toContain('name="endMode"');
    expect(html).toContain('value="count"');
    expect(html).toContain('value="date"');
    expect(html).toContain('name="occurrenceCount"');
    expect(html).toContain('name="endsOn"');
    expect(html).toContain('min="2026-09-01"');
    expect(html).toContain('max="2027-09-02"');
    expect(html).not.toContain('type="hidden" name="endMode"');
  });
});
