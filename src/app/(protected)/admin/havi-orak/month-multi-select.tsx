"use client";

import { useMemo, useState } from "react";

import { validMonth } from "@/lib/monthly-hours";

type Props = {
  initialMonths: string[];
};

const monthOptions = [
  ["01", "Január"],
  ["02", "Február"],
  ["03", "Március"],
  ["04", "Április"],
  ["05", "Május"],
  ["06", "Június"],
  ["07", "Július"],
  ["08", "Augusztus"],
  ["09", "Szeptember"],
  ["10", "Október"],
  ["11", "November"],
  ["12", "December"],
] as const;

export function MonthMultiSelect({ initialMonths }: Props) {
  const [months, setMonths] = useState(() => [...initialMonths].sort());
  const [candidate, setCandidate] = useState(initialMonths.at(-1) ?? "");
  const [candidateYear = String(new Date().getFullYear()), candidateMonth = "01"] = candidate.split("-");

  const yearOptions = useMemo(() => {
    const currentYear = new Date().getFullYear();
    const selectedYears = initialMonths.map((month) => Number(month.slice(0, 4))).filter(Number.isFinite);
    const minYear = Math.min(currentYear - 10, ...selectedYears);
    const maxYear = Math.max(currentYear + 10, ...selectedYears);
    return Array.from({ length: maxYear - minYear + 1 }, (_, index) => String(minYear + index));
  }, [initialMonths]);

  function updateCandidate(year: string, month: string) {
    setCandidate(`${year}-${month}`);
  }

  function addMonth() {
    if (!validMonth(candidate) || months.includes(candidate)) return;
    setMonths((current) => [...current, candidate].sort());
  }

  function removeMonth(month: string) {
    setMonths((current) => current.length > 1 ? current.filter((item) => item !== month) : current);
  }

  return <fieldset className="repeat-options">
    <legend>Elszámolási hónapok</legend>
    <input type="hidden" name="honapok" value={months.join(",")} />
    <div className="monthly-filter">
      <label className="desktop-month-picker">
        Hónap hozzáadása
        <input
          type="month"
          value={candidate}
          onChange={(event) => setCandidate(event.target.value)}
        />
      </label>
      <div className="mobile-month-picker" role="group" aria-label="Hónap hozzáadása">
        <span className="mobile-month-picker-label">Hónap hozzáadása</span>
        <label>
          <span>Év</span>
          <select value={candidateYear} onChange={(event) => updateCandidate(event.target.value, candidateMonth)}>
            {yearOptions.map((year) => <option key={year} value={year}>{year}</option>)}
          </select>
        </label>
        <label>
          <span>Hónap</span>
          <select value={candidateMonth} onChange={(event) => updateCandidate(candidateYear, event.target.value)}>
            {monthOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
      </div>
      <button type="button" className="secondary" onClick={addMonth}>Hozzáadás</button>
    </div>
    <div className="month-selection-list" aria-label="Kiválasztott hónapok">
      {months.map((month) => <span className="month-selection-chip" key={month}>{month}<button type="button" aria-label={`${month} eltávolítása`} onClick={() => removeMonth(month)}>×</button></span>)}
    </div>
    <p className="muted form-help">Több, egymástól független hónapot is hozzáadhatsz. Legalább egy hónap mindig marad.</p>
  </fieldset>;
}
