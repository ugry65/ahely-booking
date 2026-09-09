"use client";

import { useEffect } from "react";

const DEFAULT_PENDING_LABEL = "Folyamatban…";
const USER_EDITOR_EYEBROW = "Felhasználó szerkesztése";

function pendingLabel(button: HTMLButtonElement | HTMLInputElement) {
  if (button instanceof HTMLInputElement) return button.dataset.pendingLabel ?? DEFAULT_PENDING_LABEL;
  return button.dataset.pendingLabel ?? DEFAULT_PENDING_LABEL;
}

function isPlainPrimaryClick(event: MouseEvent) {
  return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
}

function eligibleNavigationLink(event: MouseEvent) {
  if (!isPlainPrimaryClick(event)) return null;
  if (!(event.target instanceof Element)) return null;

  const link = event.target.closest("a.button");
  if (!(link instanceof HTMLAnchorElement)) return null;
  if (link.target && link.target !== "_self") return null;
  if (link.hasAttribute("download")) return null;
  if (!link.href || link.getAttribute("href")?.startsWith("#")) return null;

  const url = new URL(link.href, window.location.href);
  if (url.origin !== window.location.origin) return null;
  return link;
}

function syncUserEditorModal() {
  const candidates = Array.from(document.querySelectorAll<HTMLElement>("section.card.wide-card.stack"));
  const editor = candidates.find((section) => section.querySelector(".eyebrow")?.textContent?.trim() === USER_EDITOR_EYEBROW) ?? null;

  for (const section of candidates) {
    if (section !== editor) {
      section.classList.remove("user-editor-modal");
      section.removeAttribute("role");
      section.removeAttribute("aria-modal");
    }
  }

  if (!editor) {
    document.body.classList.remove("user-editor-modal-open");
    return;
  }

  editor.classList.add("user-editor-modal");
  editor.setAttribute("role", "dialog");
  editor.setAttribute("aria-modal", "true");
  document.body.classList.add("user-editor-modal-open");
}

export function FormSubmitFeedback() {
  useEffect(() => {
    const handleSubmit = (event: SubmitEvent) => {
      const submitter = event.submitter;
      if (!(submitter instanceof HTMLButtonElement || submitter instanceof HTMLInputElement)) return;
      if (submitter.disabled) return;

      const originalLabel = submitter instanceof HTMLInputElement ? submitter.value : submitter.textContent ?? "";
      submitter.dataset.originalLabel = originalLabel;

      window.requestAnimationFrame(() => {
        submitter.disabled = true;
        submitter.setAttribute("aria-busy", "true");
        submitter.classList.add("is-submitting");
        const label = pendingLabel(submitter);
        if (submitter instanceof HTMLInputElement) submitter.value = label;
        else submitter.textContent = label;
      });
    };

    const handleNavigationClick = (event: MouseEvent) => {
      const link = eligibleNavigationLink(event);
      if (!link || event.defaultPrevented || link.getAttribute("aria-busy") === "true") return;

      link.dataset.originalLabel = link.textContent ?? "";
      window.requestAnimationFrame(() => {
        link.setAttribute("aria-busy", "true");
        link.classList.add("is-submitting");
        link.textContent = link.dataset.pendingLabel ?? DEFAULT_PENDING_LABEL;
      });
    };

    syncUserEditorModal();
    const observer = new MutationObserver(() => syncUserEditorModal());
    observer.observe(document.body, { childList: true, subtree: true });

    document.addEventListener("submit", handleSubmit, true);
    document.addEventListener("click", handleNavigationClick, true);
    return () => {
      observer.disconnect();
      document.body.classList.remove("user-editor-modal-open");
      document.removeEventListener("submit", handleSubmit, true);
      document.removeEventListener("click", handleNavigationClick, true);
    };
  }, []);

  return null;
}
