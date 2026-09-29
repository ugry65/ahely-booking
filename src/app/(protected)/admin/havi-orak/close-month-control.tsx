"use client";

import { useState } from "react";
import { closeMonthlySettlementPeriod } from "./actions";

export type MonthClosePreview = {
  settlement_month: string;
  can_close: boolean;
  already_closed: boolean;
  blocked_booking_count: number | string;
  participant_count: number;
  total_minutes: number | string;
  total_due_huf: number | string;
  closed_at: string | null;
};

function formatHuf(value: number | string) {
  return `${Number(value).toLocaleString("hu-HU")} Ft`;
}

function formatHours(value: number | string) {
  return `${(Number(value) / 60).toLocaleString("hu-HU", { minimumFractionDigits: 1, maximumFractionDigits: 2 })} óra`;
}

function formatMonth(value: string) {
  return new Intl.DateTimeFormat("hu-HU", { timeZone: "Europe/Budapest", year: "numeric", month: "long" }).format(new Date(`${value}T12:00:00+02:00`));
}

export function CloseMonthControl({ preview, loadError = false }: { preview: MonthClosePreview; loadError?: boolean }) {
  const [confirming, setConfirming] = useState(false);
  const monthLabel = formatMonth(preview.settlement_month);
  const closedDate = preview.closed_at ? new Intl.DateTimeFormat("hu-HU", {
    timeZone: "Europe/Budapest", year: "numeric", month: "long", day: "numeric", hour: "2-digit", minute: "2-digit",
  }).format(new Date(preview.closed_at)) : null;

  return <article className="card stack" aria-labelledby={`close-${preview.settlement_month}`}>
    <div><p className="eyebrow">Havi publikálás</p><h3 id={`close-${preview.settlement_month}`}>{monthLabel} elszámolása</h3></div>
    {loadError ? <p className="message error" role="alert">A lezárás előnézete nem tölthető be. Így a hónap nem zárható le.</p> : <>
      <dl className="monthly-close-summary">
        <div><dt>Érintett felhasználók</dt><dd>{preview.participant_count}</dd></div>
        <div><dt>Elszámolt órák</dt><dd>{formatHours(preview.total_minutes)}</dd></div>
        <div><dt>Fizetendő összesen</dt><dd>{formatHuf(preview.total_due_huf)}</dd></div>
      </dl>
      {preview.already_closed ? <p className="message success">Lezárva: {closedDate ?? "időpont nem érhető el"}. A korrekció új revisiont hoz létre.</p>
        : Number(preview.blocked_booking_count) > 0 ? <p className="message">A hónap még nem zárható le: {preview.blocked_booking_count} aktív foglalás a normál user szabályai szerint még módosítható vagy lemondható.</p>
        : !preview.can_close ? <p className="message">Ez a hónap jelenleg nem zárható le.</p>
          : <button type="button" onClick={() => setConfirming(true)}>Hónap lezárása</button>}
    </>}
    {confirming ? <div className="booking-modal-backdrop" role="dialog" aria-modal="true" aria-labelledby={`confirm-close-${preview.settlement_month}`}>
      <section className="card stack booking-modal-card">
        <div className="booking-modal-heading"><div><p className="eyebrow">Megerősítés</p><h2 id={`confirm-close-${preview.settlement_month}`}>{monthLabel} lezárása</h2></div>
          <button type="button" className="button secondary" onClick={() => setConfirming(false)} aria-label="Bezárás">×</button></div>
        <p>A zárás rögzíti az ellenőrzött havi revisioneket, és közzéteszi a résztvevők saját Foglalásaim oldalán.</p>
        <dl className="monthly-close-summary">
          <div><dt>Lezárandó hónap</dt><dd>{monthLabel}</dd></div>
          <div><dt>Érintett felhasználók</dt><dd>{preview.participant_count}</dd></div>
          <div><dt>Összes elszámolt óra</dt><dd>{formatHours(preview.total_minutes)}</dd></div>
          <div><dt>Összes fizetendő összeg</dt><dd>{formatHuf(preview.total_due_huf)}</dd></div>
        </dl>
        <form action={closeMonthlySettlementPeriod} className="booking-modal-actions">
          <input type="hidden" name="month" value={preview.settlement_month.slice(0, 7)} />
          <button type="submit" className="danger-button">Lezárás megerősítése</button>
          <button type="button" className="button secondary" onClick={() => setConfirming(false)}>Mégse</button>
        </form>
      </section>
    </div> : null}
  </article>;
}
