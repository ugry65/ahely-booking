"use client";

import { useEffect } from "react";

const DEFAULT_PENDING_LABEL = "Folyamatban…";

function pendingLabel(button: HTMLButtonElement | HTMLInputElement) {
  if (button instanceof HTMLInputElement) return button.dataset.pendingLabel ?? DEFAULT_PENDING_LABEL;
  return button.dataset.pendingLabel ?? DEFAULT_PENDING_LABEL;
}

export function FormSubmitFeedback() {
  useEffect(() => {
    const handleSubmit = (event: SubmitEvent) => {
      const submitter = event.submitter;
      if (!(submitter instanceof HTMLButtonElement || submitter instanceof HTMLInputElement)) return;
      if (submitter.disabled) return;

      const originalLabel = submitter instanceof HTMLInputElement ? submitter.value : submitter.textContent ?? "";
      submitter.dataset.originalLabel = originalLabel;

      // A submit eseményt és a FormData összeállítását nem zavarjuk meg: a vizuális
      // állapotot a következő frame-ben kapcsoljuk be. Server action/redirect után
      // az oldal újrarenderelése visszaállítja a gomb normál állapotát.
      window.requestAnimationFrame(() => {
        submitter.disabled = true;
        submitter.setAttribute("aria-busy", "true");
        submitter.classList.add("is-submitting");
        const label = pendingLabel(submitter);
        if (submitter instanceof HTMLInputElement) submitter.value = label;
        else submitter.textContent = label;
      });
    };

    document.addEventListener("submit", handleSubmit, true);
    return () => document.removeEventListener("submit", handleSubmit, true);
  }, []);

  return null;
}
