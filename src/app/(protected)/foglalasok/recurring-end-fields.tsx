"use client";

import { useEffect, useId, useRef, useState } from "react";

type EndMode = "count" | "date";

function shiftDate(date: string, days: number) {
  const [year, month, day] = date.split("-").map(Number);
  if (!year || !month || !day) return "";
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

export function RecurringEndFields({ initialDate }: { initialDate: string }) {
  const [endMode, setEndMode] = useState<EndMode>("count");
  const [firstDate, setFirstDate] = useState(initialDate);
  const rootRef = useRef<HTMLFieldSetElement>(null);
  const id = useId();

  useEffect(() => {
    const form = rootRef.current?.closest("form");
    if (!form) return;

    const refreshFirstDate = () => {
      const control = form.elements.namedItem("date");
      if (control instanceof HTMLInputElement && control.value) setFirstDate(control.value);
    };

    refreshFirstDate();
    form.addEventListener("change", refreshFirstDate);
    form.addEventListener("input", refreshFirstDate);
    return () => {
      form.removeEventListener("change", refreshFirstDate);
      form.removeEventListener("input", refreshFirstDate);
    };
  }, []);

  useEffect(() => {
    const form = rootRef.current?.closest("form");
    form?.dispatchEvent(new Event("input", { bubbles: true }));
  }, [endMode]);

  const maximumEndDate = shiftDate(firstDate, 366);
  const countRadioId = `${id}-count-radio`;
  const countInputId = `${id}-count-input`;
  const dateRadioId = `${id}-date-radio`;
  const dateInputId = `${id}-date-input`;

  return <fieldset ref={rootRef} className="recurring-end-fields">
    <legend>Sorozat vége</legend>
    <div className={`recurring-end-choice ${endMode === "count" ? "active" : ""}`}>
      <label className="inline-check" htmlFor={countRadioId}>
        <input id={countRadioId} type="radio" name="endMode" value="count" checked={endMode === "count"} onChange={() => setEndMode("count")} />
        Alkalmak száma alapján
      </label>
      <label htmlFor={countInputId}>Alkalmak száma
        <input id={countInputId} name="occurrenceCount" type="number" min="1" max="400" defaultValue="6" required={endMode === "count"} disabled={endMode !== "count"} />
      </label>
    </div>
    <div className={`recurring-end-choice ${endMode === "date" ? "active" : ""}`}>
      <label className="inline-check" htmlFor={dateRadioId}>
        <input id={dateRadioId} type="radio" name="endMode" value="date" checked={endMode === "date"} onChange={() => setEndMode("date")} />
        Végdátum alapján
      </label>
      <label htmlFor={dateInputId}>Befejezés dátuma
        <input id={dateInputId} name="endsOn" type="date" min={firstDate} max={maximumEndDate} required={endMode === "date"} disabled={endMode !== "date"} />
      </label>
    </div>
    <p className="muted form-help">A végdátum napján csak akkor jön létre alkalom, ha az a választott ismétlődési gyakoriság szerint esedékes.</p>
  </fieldset>;
}
