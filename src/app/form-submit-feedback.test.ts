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

  it("shows an immediate pending state and blocks duplicate form submission", () => {
    const source = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.tsx"), "utf8");
    expect(source).toContain('document.addEventListener("submit", handleSubmit, true)');
    expect(source).toContain('element.dataset.pendingScheduled = "true"');
    expect(source).toContain("schedulePendingState(submitter, () => !event.defaultPrevented)");
    expect(source).toContain("if (!shouldApply())");
    expect(source).toContain("event.preventDefault()");
    expect(source).toContain("element.disabled = true");
    expect(source).toContain('element.setAttribute("aria-busy", "true")');
    expect(source).toContain('element.classList.add("is-submitting")');
    expect(source).toContain('"Folyamatban…"');
  });

  it("shows pending feedback for plain primary clicks on internal button links", () => {
    const source = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.tsx"), "utf8");
    expect(source).toContain('document.addEventListener("click", handleNavigationClick, true)');
    expect(source).toContain('event.target.closest("a.button")');
    expect(source).toContain("url.origin !== window.location.origin");
    expect(source).toContain('link.getAttribute("aria-busy") === "true"');
    expect(source).toContain("!event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey");
    expect(source).toContain('link.hasAttribute("download")');
  });

  it("clears pending feedback after navigation or action failure signals", () => {
    const source = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.tsx"), "utf8");
    expect(source).toContain("PENDING_RESET_TIMEOUT_MS = 30_000");
    expect(source).toContain('window.addEventListener("pageshow", resetAllPending)');
    expect(source).toContain('window.addEventListener("popstate", resetAllPending)');
    expect(source).toContain("const handleRouteMutation = () =>");
    expect(source).toContain("const observer = new MutationObserver(handleRouteMutation)");
    expect(source).toContain('window.addEventListener("error", resetAllPending)');
    expect(source).toContain('window.addEventListener("unhandledrejection", resetAllPending)');
  });

  it("renders the selected user editor as an accessible, scrollable modal", () => {
    const source = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.tsx"), "utf8");
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.css"), "utf8");
    expect(source).toContain('USER_EDITOR_EYEBROW = "Felhasználó szerkesztése"');
    expect(source).toContain('editor.setAttribute("role", "dialog")');
    expect(source).toContain('editor.setAttribute("aria-modal", "true")');
    expect(source).toContain('editor.setAttribute("aria-labelledby", title.id)');
    expect(source).toContain('event.key !== "Escape"');
    expect(source).toContain("new MutationObserver(syncUserEditorModal)");
    expect(css).toContain("body.user-editor-modal-open::before");
    expect(css).toContain(".user-editor-modal");
    expect(css).toContain("max-height: 90vh");
    expect(css).toContain("max-height: calc(100dvh - 24px)");
    expect(css).toContain("overflow: auto");
  });

  it("keeps a visible pressed and pending state in CSS", () => {
    const css = fs.readFileSync(path.join(process.cwd(), "src", "app", "form-submit-feedback.css"), "utf8");
    expect(css).toContain('a.button:active:not([aria-busy="true"])');
    expect(css).toContain("a.button.is-submitting");
    expect(css).toContain('a.button[aria-busy="true"]');
  });
});
