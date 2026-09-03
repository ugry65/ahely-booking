"use client";

import { useMemo, useState } from "react";

import { validMonth } from "@/lib/monthly-hours";

type Props = {
  initialMonth: string;
  label: string;
  name: string;
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

export function ResponsiveMonthField({ initialMonth, label, name }: Props) {
  const fallbackMonth = validMonth(initialMonth) ? initialMonth : "2000-01";
  const [value, setValue] = useState(fallbackMonth);
  const [year, month] = value.split("-");
  const yearOptions = useMemo(() => {
    const initialYear = Number(fallbackMonth.slice(0, 4));
    return Array.from({ length: 21 }, (_, index) => String(initialYear - 10 + index));
  }, [fallbackMonth]);

  function update(nextYear: string, nextMonth: string) {
    setValue(`${nextYear}-${nextMonth}`);
  }

  return <div className="responsive-month-field">
    <input type="hidden" name={name} value={value} />
    <label className="desktop-month-picker">
      {label}
      <input type="month" value={value} onChange={(event) => setValue(event.target.value)} required />
    </label>
    <div className="mobile-month-picker" role="group" aria-label={label}>
      <span className="mobile-month-picker-label">{label}</span>
      <label>
        <span>Év</span>
        <select value={year} onChange={(event) => update(event.target.value, month)}>
          {yearOptions.map((option) => <option key={option} value={option}>{option}</option>)}
        </select>
      </label>
      <label>
        <span>Hónap</span>
        <select value={month} onChange={(event) => update(year, event.target.value)}>
          {monthOptions.map(([option, optionLabel]) => <option key={option} value={option}>{optionLabel}</option>)}
        </select>
      </label>
    </div>
  </div>;
}
