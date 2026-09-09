import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("form submit feedback", () => {
  it("mounts the global submit feedback helper from the root layout", () => {
    const layout = fs.readFileSync(path.join(process.cwd(), "src", "app", "layout.tsx"), "utf8");
    expect(layout).toContain('import { FormSubmitFeedback } from "./form-submit-feedback"');
    expect(layout).toContain("<FormSubmitFeedback />");
    expect(layout).toContain('import "./form-submit-feedback.css"');
  });

  it("shows an immediate pending state and blocks duplicate submission", () => {
    const source = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.tsx"), "utf8");
    expect(source).toContain('document.addEventListener("submit", handleSubmit, true)');
    expect(source).toContain('submitter.disabled = true');
    expect(source).toContain('submitter.setAttribute("aria-busy", "true")');
    expect(source).toContain('submitter.classList.add("is-submitting")');
    expect(source).toContain('"Folyamatban…"');
  });

  it("keeps a visible pressed and pending state in CSS", () => {
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.css"), "utf8");
    expect(css).toContain(":active:not(:disabled)");
    expect(css).toContain(".is-submitting");
    expect(css).toContain('[aria-busy="true"]');
  });
});
