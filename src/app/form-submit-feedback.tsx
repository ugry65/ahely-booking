"use client";

import { useEffect } from "react";

const DEFAULT_PENDING_LABEL = "Folyamatban…";
const USER_EDITOR_EYEBROW = "Felhasználó szerkesztése";
const PENDING_RESET_TIMEOUT_MS = 30_000;

type PendingElement = HTMLButtonElement | HTMLInputElement | HTMLAnchorElement;

function pendingLabel(element: PendingElement) {
  return element.dataset.pendingLabel ?? DEFAULT_PENDING_LABEL;
}

function restorePendingElement(element: PendingElement) {
  const originalLabel = element.dataset.originalLabel;
  if (originalLabel !== undefined) {
    if (element instanceof HTMLInputElement) element.value = originalLabel;
    else element.textContent = originalLabel;
  }
  if (element instanceof HTMLButtonElement || element instanceof HTMLInputElement) element.disabled = false;
  element.removeAttribute("aria-busy");
  element.classList.remove("is-submitting");
  delete element.dataset.originalLabel;
  delete element.dataset.pendingScheduled;
}

function resetAllPending() {
  document.querySelectorAll<PendingElement>(".is-submitting, [data-pending-scheduled='true']")
    .forEach(restorePendingElement);
}

function schedulePendingState(element: PendingElement) {
  element.dataset.pendingScheduled = "true";
  element.dataset.originalLabel = element instanceof HTMLInputElement ? element.value : element.textContent ?? "";

  window.requestAnimationFrame(() => {
    if (!element.isConnected) return;
    if (element instanceof HTMLButtonElement || element instanceof HTMLInputElement) element.disabled = true;
    element.setAttribute("aria-busy", "true");
    element.classList.add("is-submitting");
    const label = pendingLabel(element);
    if (element instanceof HTMLInputElement) element.value = label;
    else element.textContent = label;
  });

  window.setTimeout(() => {
    if (element.isConnected) restorePendingElement(element);
  }, PENDING_RESET_TIMEOUT_MS);
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
      section.removeAttribute("aria-labelledby");
    }
  }

  if (!editor) {
    document.body.classList.remove("user-editor-modal-open");
    return;
  }

  const wasModal = editor.classList.contains("user-editor-modal");
  const title = editor.querySelector<HTMLElement>("h2");
  if (title && !title.id) title.id = "user-editor-modal-title";
  editor.classList.add("user-editor-modal");
  editor.setAttribute("role", "dialog");
  editor.setAttribute("aria-modal", "true");
  editor.setAttribute("tabindex", "-1");
  if (title) editor.setAttribute("aria-labelledby", title.id);
  document.body.classList.add("user-editor-modal-open");
  if (!wasModal) editor.focus({ preventScroll: true });
}

export function FormSubmitFeedback() {
  useEffect(() => {
    const handleSubmit = (event: SubmitEvent) => {
      const submitter = event.submitter;
      if (!(submitter instanceof HTMLButtonElement || submitter instanceof HTMLInputElement)) return;
      if (submitter.disabled) return;
      if (submitter.dataset.pendingScheduled === "true") {
        event.preventDefault();
        return;
      }
      schedulePendingState(submitter);
    };

    const handleNavigationClick = (event: MouseEvent) => {
      const link = eligibleNavigationLink(event);
      if (!link || event.defaultPrevented) return;
      if (link.getAttribute("aria-busy") === "true" || link.dataset.pendingScheduled === "true") {
        event.preventDefault();
        return;
      }
      schedulePendingState(link);
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      const editor = document.querySelector<HTMLElement>(".user-editor-modal");
      const closeLink = editor?.querySelector<HTMLAnchorElement>('a.button[href^="/admin/felhasznalok"]');
      closeLink?.click();
    };

    syncUserEditorModal();
    const observer = new MutationObserver(syncUserEditorModal);
    observer.observe(document.body, { childList: true, subtree: true });

    document.addEventListener("submit", handleSubmit, true);
    document.addEventListener("click", handleNavigationClick, true);
    document.addEventListener("keydown", handleKeyDown);
    window.addEventListener("pageshow", resetAllPending);
    window.addEventListener("popstate", resetAllPending);
    window.addEventListener("error", resetAllPending);
    window.addEventListener("unhandledrejection", resetAllPending);
    return () => {
      observer.disconnect();
      resetAllPending();
      document.body.classList.remove("user-editor-modal-open");
      document.removeEventListener("submit", handleSubmit, true);
      document.removeEventListener("click", handleNavigationClick, true);
      document.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("pageshow", resetAllPending);
      window.removeEventListener("popstate", resetAllPending);
      window.removeEventListener("error", resetAllPending);
      window.removeEventListener("unhandledrejection", resetAllPending);
    };
  }, []);

  return null;
}
