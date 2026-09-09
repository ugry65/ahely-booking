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

  it("shows pending feedback for plain primary clicks on internal button links", () => {
    const source = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.tsx"), "utf8");
    expect(source).toContain('document.addEventListener("click", handleNavigationClick, true)');
    expect(source).toContain('event.target.closest("a.button")');
    expect(source).toContain('url.origin !== window.location.origin');
    expect(source).toContain('link.setAttribute("aria-busy", "true")');
    expect(source).toContain('link.classList.add("is-submitting")');
    expect(source).toContain('link.textContent = link.dataset.pendingLabel ?? DEFAULT_PENDING_LABEL');
    expect(source).toContain('!event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey');
    expect(source).toContain('link.hasAttribute("download")');
  });

  it("renders the selected user editor as an accessible modal", () => {
    const source = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.tsx"), "utf8");
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.css"), "utf8");
    expect(source).toContain('USER_EDITOR_EYEBROW = "Felhasználó szerkesztése"');
    expect(source).toContain('section.classList.remove("user-editor-modal")');
    expect(source).toContain('editor.classList.add("user-editor-modal")');
    expect(source).toContain('editor.setAttribute("role", "dialog")');
    expect(source).toContain('editor.setAttribute("aria-modal", "true")');
    expect(source).toContain('new MutationObserver(() => syncUserEditorModal())');
    expect(css).toContain('body.user-editor-modal-open::before');
    expect(css).toContain('.user-editor-modal');
    expect(css).toContain('max-height: 90vh');
  });

  it("keeps a visible pressed and pending state in CSS", () => {
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.css"), "utf8");
    expect(css).toContain(":active:not(:disabled)");
    expect(css).toContain("a.button:active:not([aria-busy=\"true\"])");
    expect(css).toContain("a.button.is-submitting");
    expect(css).toContain('a.button[aria-busy="true"]');
  });
});
