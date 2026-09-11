"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

type Target = "previous" | "today" | "next";

function hrefFor(date: string) {
  return `/foglalasok?datum=${date}`;
}

export function CalendarDateNavigation({ previousDate, today, nextDate, selectedDate }: {
  previousDate: string;
  today: string;
  nextDate: string;
  selectedDate: string;
}) {
  const router = useRouter();
  const [pendingTarget, setPendingTarget] = useState<Target | null>(null);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  function clearPending() {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    timeoutRef.current = null;
    setPendingTarget(null);
  }

  useEffect(() => {
    clearPending();
    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
    // selectedDate is intentionally the navigation completion signal.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedDate]);

  function navigate(target: Target, date: string) {
    if (pendingTarget) return;
    setPendingTarget(target);
    router.push(hrefFor(date));

    // Fail-safe: a network/navigation failure must never leave the controls stuck.
    timeoutRef.current = setTimeout(() => setPendingTarget(null), 8000);
  }

  return (
    <nav className="date-nav calendar-date-nav" aria-label="Naptári nap választása">
      <button
        type="button"
        className="button secondary"
        aria-label="Előző nap"
        aria-busy={pendingTarget === "previous"}
        disabled={pendingTarget !== null}
        onClick={() => navigate("previous", previousDate)}
      >
        {pendingTarget === "previous" ? "Folyamatban…" : "←"}
      </button>
      <button
        type="button"
        className="button secondary"
        aria-busy={pendingTarget === "today"}
        disabled={pendingTarget !== null}
        onClick={() => navigate("today", today)}
      >
        {pendingTarget === "today" ? "Folyamatban…" : "Ma"}
      </button>
      <button
        type="button"
        className="button secondary"
        aria-label="Következő nap"
        aria-busy={pendingTarget === "next"}
        disabled={pendingTarget !== null}
        onClick={() => navigate("next", nextDate)}
      >
        {pendingTarget === "next" ? "Folyamatban…" : "→"}
      </button>
    </nav>
  );
}
