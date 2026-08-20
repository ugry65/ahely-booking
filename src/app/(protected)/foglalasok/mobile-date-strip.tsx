"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

function shiftDate(date: string, days: number) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

function weekday(date: string) {
  return new Intl.DateTimeFormat("hu-HU", { timeZone: "UTC", weekday: "short" }).format(new Date(`${date}T12:00:00Z`)).replace(".", "");
}

function dayNumber(date: string) { return Number(date.slice(-2)); }
function monthKey(date: string) { return date.slice(0, 7); }
function shiftMonth(month: string, delta: number) {
  const [year, mon] = month.split("-").map(Number);
  return new Date(Date.UTC(year, mon - 1 + delta, 1)).toISOString().slice(0, 7);
}
function monthTitle(month: string) {
  return new Intl.DateTimeFormat("hu-HU", { timeZone: "UTC", year: "numeric", month: "short" }).format(new Date(`${month}-01T12:00:00Z`));
}
function monthDays(month: string) {
  const [year, mon] = month.split("-").map(Number);
  const first = new Date(Date.UTC(year, mon - 1, 1));
  const mondayIndex = (first.getUTCDay() + 6) % 7;
  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(Date.UTC(year, mon - 1, 1 - mondayIndex + index));
    return date.toISOString().slice(0, 10);
  });
}

export function MobileDateStrip({ selectedDate }: { selectedDate: string }) {
  const router = useRouter();
  const [calendarOpen, setCalendarOpen] = useState(false);
  const [visibleMonth, setVisibleMonth] = useState(monthKey(selectedDate));
  const dates = Array.from({ length: 7 }, (_, index) => shiftDate(selectedDate, index));
  const calendarDates = useMemo(() => monthDays(visibleMonth), [visibleMonth]);

  function go(date: string) {
    setCalendarOpen(false);
    setVisibleMonth(monthKey(date));
    router.push(`/foglalasok?datum=${date}`);
  }

  return (
    <div className="mobile-date-toolbar" aria-label="Dátumválasztó">
      <div className="mobile-week-strip">
        {dates.map((date) => (
          <button key={date} type="button" className={`mobile-day-button ${date === selectedDate ? "active" : ""}`} onClick={() => go(date)} aria-current={date === selectedDate ? "date" : undefined}>
            <span>{weekday(date)}</span><strong>{dayNumber(date)}</strong>
          </button>
        ))}
        <button type="button" className="mobile-calendar-button" onClick={() => setCalendarOpen((value) => !value)} aria-label="Naptár megnyitása" aria-expanded={calendarOpen}>▦</button>
      </div>

      {calendarOpen ? (
        <div className="mobile-calendar-popover" role="dialog" aria-label="Dátum kiválasztása">
          <div className="mobile-calendar-month-nav">
            <button type="button" className="mobile-calendar-arrow" onClick={() => setVisibleMonth(shiftMonth(visibleMonth, -1))} aria-label="Előző hónap">‹</button>
            <strong>{monthTitle(visibleMonth)}</strong>
            <button type="button" className="mobile-calendar-arrow" onClick={() => setVisibleMonth(shiftMonth(visibleMonth, 1))} aria-label="Következő hónap">›</button>
          </div>
          <div className="mobile-calendar-weekdays" aria-hidden="true"><span>H</span><span>K</span><span>Sze</span><span>Cs</span><span>P</span><span>Szo</span><span>V</span></div>
          <div className="mobile-calendar-days">
            {calendarDates.map((date) => (
              <button key={date} type="button" className={`${monthKey(date) !== visibleMonth ? "outside" : ""} ${date === selectedDate ? "selected" : ""}`} onClick={() => go(date)}>{dayNumber(date)}</button>
            ))}
          </div>
          <button type="button" className="mobile-calendar-today" onClick={() => go(new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()))}>Ma</button>
        </div>
      ) : null}
    </div>
  );
}
