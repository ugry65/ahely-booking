"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { buildRecurringOccurrenceDates, type PreviewFrequency } from "@/lib/recurring-occurrences";
import styles from "./recurring-exception-calendar.module.css";

type MonthGroup = { key: string; year: number; month: number; dates: Set<string> };

function readString(formData: FormData, name: string) { return String(formData.get(name) ?? ""); }
function monthLabel(year: number, month: number) { return new Intl.DateTimeFormat("hu-HU", { year: "numeric", month: "long", timeZone: "UTC" }).format(new Date(Date.UTC(year, month - 1, 1))); }
function daysInMonth(year: number, month: number) { return new Date(Date.UTC(year, month, 0)).getUTCDate(); }
function mondayIndex(year: number, month: number) { const sundayBased = new Date(Date.UTC(year, month - 1, 1)).getUTCDay(); return (sundayBased + 6) % 7; }
function isoDay(year: number, month: number, day: number) { return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`; }

export function RecurringExceptionCalendar() {
  const rootRef = useRef<HTMLDivElement>(null);
  const [occurrenceDates, setOccurrenceDates] = useState<string[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());

  useEffect(() => {
    const form = rootRef.current?.closest("form");
    if (!form) return;

    const refresh = () => {
      const data = new FormData(form);
      const endMode = readString(data, "endMode") === "date" ? "date" : "count";
      const rawCount = Number(readString(data, "occurrenceCount"));
      const frequency = readString(data, "frequency") as PreviewFrequency;
      const dates = buildRecurringOccurrenceDates({
        firstDate: readString(data, "date"),
        frequency,
        endMode,
        occurrenceCount: Number.isInteger(rawCount) ? rawCount : null,
        endsOn: readString(data, "endsOn") || null,
      });
      setOccurrenceDates(dates);
      setSelected((current) => new Set([...current].filter((date) => dates.includes(date))));
    };

    refresh();
    form.addEventListener("change", refresh);
    form.addEventListener("input", refresh);
    return () => {
      form.removeEventListener("change", refresh);
      form.removeEventListener("input", refresh);
    };
  }, []);

  const months = useMemo(() => {
    const map = new Map<string, MonthGroup>();
    for (const date of occurrenceDates) {
      const [year, month] = date.split("-").map(Number);
      const key = `${year}-${String(month).padStart(2, "0")}`;
      const group = map.get(key) ?? { key, year, month, dates: new Set<string>() };
      group.dates.add(date);
      map.set(key, group);
    }
    return [...map.values()];
  }, [occurrenceDates]);

  const selectedDates = [...selected].sort();
  const createdCount = Math.max(0, occurrenceDates.length - selectedDates.length);

  function toggle(date: string) {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(date)) next.delete(date); else next.add(date);
      return next;
    });
  }

  return <div ref={rootRef} className={styles.wrapper}>
    <input type="hidden" name="exceptionDates" value={selectedDates.join(",")} />
    <div>
      <strong>Kivételdátumok</strong>
      <p className="muted form-help">Kattints a sorozat egy vagy több tényleges alkalmára, ha azt ki szeretnéd hagyni. Újabb kattintással visszavonható.</p>
    </div>

    {occurrenceDates.length ? <>
      <p className={styles.summary}><strong>{createdCount}</strong> alkalom létrejön, <strong>{selectedDates.length}</strong> alkalom kimarad.</p>
      <div className={styles.months}>
        {months.map((group) => {
          const blanks = mondayIndex(group.year, group.month);
          const count = daysInMonth(group.year, group.month);
          return <section className={styles.month} key={group.key} aria-label={monthLabel(group.year, group.month)}>
            <h3>{monthLabel(group.year, group.month)}</h3>
            <div className={styles.weekdays}>{["H", "K", "Sze", "Cs", "P", "Szo", "V"].map((day) => <span key={day}>{day}</span>)}</div>
            <div className={styles.grid}>
              {Array.from({ length: blanks }, (_, index) => <span key={`blank-${index}`} className={styles.empty} />)}
              {Array.from({ length: count }, (_, index) => index + 1).map((day) => {
                const date = isoDay(group.year, group.month, day);
                const isOccurrence = group.dates.has(date);
                const isSelected = selected.has(date);
                return isOccurrence
                  ? <button key={date} type="button" className={`${styles.day} ${styles.occurrence} ${isSelected ? styles.selected : ""}`} aria-pressed={isSelected} onClick={() => toggle(date)} title={isSelected ? "Kivétel – kattints a visszavonáshoz" : "Sorozat alkalma – kattints a kihagyáshoz"}>{day}</button>
                  : <span key={date} className={styles.day}>{day}</span>;
              })}
            </div>
          </section>;
        })}
      </div>
    </> : <p className="muted">Állítsd be az első dátumot, gyakoriságot és a sorozat végét; ezután itt megjelennek a kiválasztható alkalmak.</p>}
  </div>;
}
