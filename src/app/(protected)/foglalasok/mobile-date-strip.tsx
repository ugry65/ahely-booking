"use client";

import { useRef } from "react";
import { useRouter } from "next/navigation";

function shiftDate(date: string, days: number) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

function weekday(date: string) {
  return new Intl.DateTimeFormat("hu-HU", { timeZone: "UTC", weekday: "short" })
    .format(new Date(`${date}T12:00:00Z`))
    .replace(".", "");
}

function dayNumber(date: string) {
  return Number(date.slice(-2));
}

export function MobileDateStrip({ selectedDate }: { selectedDate: string }) {
  const router = useRouter();
  const dateInputRef = useRef<HTMLInputElement>(null);
  const dates = Array.from({ length: 7 }, (_, index) => shiftDate(selectedDate, index - 3));

  function go(date: string) {
    router.push(`/foglalasok?datum=${date}`);
  }

  function openCalendar() {
    const input = dateInputRef.current;
    if (!input) return;
    try {
      input.showPicker?.();
    } catch {
      input.click();
    }
  }

  return (
    <div className="mobile-date-toolbar" aria-label="Dátumválasztó">
      <div className="mobile-week-strip">
        {dates.map((date) => (
          <button
            key={date}
            type="button"
            className={`mobile-day-button ${date === selectedDate ? "active" : ""}`}
            onClick={() => go(date)}
            aria-current={date === selectedDate ? "date" : undefined}
          >
            <span>{weekday(date)}</span>
            <strong>{dayNumber(date)}</strong>
          </button>
        ))}
        <button type="button" className="mobile-calendar-button" onClick={openCalendar} aria-label="Ugrás dátumra">▦</button>
        <input
          ref={dateInputRef}
          className="mobile-native-date-input"
          type="date"
          value={selectedDate}
          onChange={(event) => event.target.value && go(event.target.value)}
          aria-hidden="true"
          tabIndex={-1}
        />
      </div>
    </div>
  );
}
