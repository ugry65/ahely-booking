"use client";

import { useState } from "react";

import { validMonth } from "@/lib/monthly-hours";

type Props = {
  initialMonths: string[];
};

export function MonthMultiSelect({ initialMonths }: Props) {
  const [months, setMonths] = useState(() => [...initialMonths].sort());
  const [candidate, setCandidate] = useState(initialMonths.at(-1) ?? "");

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
      <label>Hónap hozzáadása<input type="month" value={candidate} onChange={(event) => setCandidate(event.target.value)} /></label>
      <button type="button" className="secondary" onClick={addMonth}>Hozzáadás</button>
    </div>
    <div className="month-selection-list" aria-label="Kiválasztott hónapok">
      {months.map((month) => <span className="month-selection-chip" key={month}>{month}<button type="button" aria-label={`${month} eltávolítása`} onClick={() => removeMonth(month)}>×</button></span>)}
    </div>
    <p className="muted form-help">Több, egymástól független hónapot is hozzáadhatsz. Legalább egy hónap mindig marad.</p>
  </fieldset>;
}
