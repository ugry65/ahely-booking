"use client";
import { useMemo, useState } from "react";
import { bookingHourParts, cancellationPreview } from "@/lib/partial-booking-cancellation";
import { cancelCalendarBookingParts } from "./actions";
type Booking = { booking_id: string; start_at: string; end_at: string; updated_at: string | null; series_id: string | null };
const time = (iso: string) => new Intl.DateTimeFormat("hu-HU", { timeZone: "Europe/Budapest", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
export function PartialCancellationDialog({ booking, date, onClose }: { booking: Booking; date: string; onClose: () => void }) {
  const parts = useMemo(() => bookingHourParts(booking.start_at, booking.end_at), [booking.start_at,booking.end_at]);
  const [selected, setSelected] = useState<number[]>([]);
  const [key, setKey] = useState(() => crypto.randomUUID());
  const ranges = selected.map(i => parts[i]);
  const preview = cancellationPreview(booking.start_at,booking.end_at,ranges);
  return <div className="booking-modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="partial-cancel-title"><section className="card stack booking-modal-card">
    <div className="booking-modal-heading"><h2 id="partial-cancel-title">Órák lemondása</h2><button type="button" className="button secondary" onClick={onClose} aria-label="Bezárás">×</button></div>
    <p>Jelöld ki a lemondandó részeket. A határidőt minden kijelölt rész saját kezdetétől ellenőrizzük. A megmaradó részek legalább 60 percesek legyenek.</p>
    {booking.series_id ? <p className="message">Csak ezt az egy sorozatalkalmat érinti. A felbontott részek később külön szerkeszthetők.</p> : null}
    <form action={cancelCalendarBookingParts} className="stack">
      <input type="hidden" name="bookingId" value={booking.booking_id}/><input type="hidden" name="expectedUpdatedAt" value={booking.updated_at ?? ""}/>
      <input type="hidden" name="date" value={date}/><input type="hidden" name="idempotencyKey" value={key}/><input type="hidden" name="ranges" value={JSON.stringify(ranges)}/>
      <fieldset className="stack"><legend>Lemondandó időszakok</legend>{parts.map((part,i) => <label key={part.start}><input type="checkbox" checked={selected.includes(i)} onChange={e => { setSelected(old => e.target.checked ? [...old,i] : old.filter(n => n!==i)); setKey(crypto.randomUUID()); }}/>{time(part.start)}–{time(part.end)}</label>)}</fieldset>
      <div role="status" aria-live="polite">{preview.ok ? <><strong>Megmarad:</strong>{preview.remaining.length ? <ul>{preview.remaining.map(r => <li key={r.start}>{time(r.start)}–{time(r.end)}</li>)}</ul> : <p>Semmi: a teljes kiválasztott foglalás lemondásra kerül.</p>}</> : <p>{preview.error}</p>}</div>
      <p className="muted">A befizetés az eredeti foglaláscsoporthoz kapcsolva megmarad, a havi díj és egyenleg újraszámolódik.</p>
      <label>Indok<textarea name="reason" maxLength={500} rows={2}/></label>
      <label><input type="checkbox" name="confirm" value="yes" required/> Ellenőriztem a lemondandó és a megmaradó időszakokat.</label>
      <div className="booking-modal-actions"><button type="submit" className="danger-button" disabled={!preview.ok || !booking.updated_at}>Kijelölt órák lemondása</button><button type="button" className="button secondary" onClick={onClose}>Mégse</button></div>
    </form>
  </section></div>;
}
