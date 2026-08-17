import { describe, expect, it } from "vitest";

import { checkboxValue } from "./form-values";

describe("checkboxValue", () => {
  it("a rejtett false és a bejelölt true értékből true-t ad", () => {
    const data = new FormData();
    data.append("visible", "false");
    data.append("visible", "true");
    expect(checkboxValue(data, "visible")).toBe(true);
  });

  it("kikapcsolt checkboxnál false-t ad", () => {
    const data = new FormData();
    data.append("visible", "false");
    expect(checkboxValue(data, "visible")).toBe(false);
  });

  it("hiányzó mezőnél fail-closed false-t ad", () => {
    expect(checkboxValue(new FormData(), "visible")).toBe(false);
  });
});
