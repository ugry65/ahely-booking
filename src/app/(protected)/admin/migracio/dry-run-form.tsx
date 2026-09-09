"use client";

import { FormEvent, useState } from "react";

type DryRunResult = {
  valid: boolean;
  ignoredPricingFields: string[];
  issues: { line: number; code: string; message: string }[];
  users: { email: string; firstName: string; lastName: string; phone: string | null; accessTags: string[] }[];
  bookings: { line: number; holderEmail: string; roomSource: string; roomTarget: string; startLocal: string; endLocal: string; durationMinutes: number; bookingTitle: string | null }[];
  summary: {
    sourceRows: number;
    normalizedUsers: number;
    normalizedBookings: number;
    totalMinutes: number;
    totalHours: number;
    bookingsByRoom: Record<string, number>;
    bookingsByUser: Record<string, number>;
  };
};

export function MigrationDryRunForm() {
  const [result, setResult] = useState<DryRunResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const response = await fetch("/api/internal/migration-dry-run", {
        method: "POST",
        body: new FormData(event.currentTarget),
      });
      const body = await response.json();
      if (!response.ok && !body.summary) {
        setError(body.error ?? "A dry-run nem futott le.");
        return;
      }
      setResult(body as DryRunResult);
    } catch {
      setError("A dry-run technikai hiba miatt nem futott le.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <form onSubmit={submit} className="card stack">
        <h2>AllBooked CSV dry-run</h2>
        <p className="muted">Csak ellenőrzés: nem ír adatbázisba, nem hoz létre felhasználót vagy foglalást, és nem küld e-mailt.</p>
        <label>Booking export CSV<input name="file" type="file" accept=".csv,text/csv" required /></label>
        <button type="submit" disabled={busy}>{busy ? "Ellenőrzés folyamatban…" : "Dry-run futtatása"}</button>
      </form>

      {error ? <p className="message error" role="alert">{error}</p> : null}
      {result ? <section className="card stack">
        <div><p className="eyebrow">Dry-run eredmény</p><h2>{result.valid ? "PASS" : "ELLENŐRZÉST IGÉNYEL"}</h2></div>
        <div className="admin-grid">
          <p><strong>Forrássorok:</strong> {result.summary.sourceRows}</p>
          <p><strong>Felhasználók:</strong> {result.summary.normalizedUsers}</p>
          <p><strong>Foglalások:</strong> {result.summary.normalizedBookings}</p>
          <p><strong>Összes óra:</strong> {result.summary.totalHours}</p>
        </div>
        <div><h3>Foglalások userenként</h3>{Object.entries(result.summary.bookingsByUser).map(([email, count]) => <p key={email}>{email}: {count} db</p>)}</div>
        <div><h3>Foglalások helyiségenként</h3>{Object.entries(result.summary.bookingsByRoom).map(([room, count]) => <p key={room}>{room}: {count} db</p>)}</div>
        <div><h3>Kizárt legacy pénzügyi mezők</h3><p className="muted">{result.ignoredPricingFields.join(", ")}</p></div>
        {result.issues.length ? <div><h3>Hibák / kézi ellenőrzések</h3><ul>{result.issues.map((issue, index) => <li key={`${issue.line}-${issue.code}-${index}`}>{issue.line}. sor – {issue.message}</li>)}</ul></div> : <p className="message success" role="status">Nincs blokkoló eltérés.</p>}
      </section> : null}
    </div>
  );
}
