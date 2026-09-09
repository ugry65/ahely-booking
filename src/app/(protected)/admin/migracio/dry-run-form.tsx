"use client";

import { FormEvent, useState } from "react";

const IMPORT_CONFIRMATION = "IMPORT-PAPP-DALMA-PRODUCTION";

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
  const [file, setFile] = useState<File | null>(null);
  const [confirmation, setConfirmation] = useState("");
  const [importResult, setImportResult] = useState<Record<string, unknown> | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setResult(null);
    setImportResult(null);
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

  async function runImport() {
    if (!file || confirmation !== IMPORT_CONFIRMATION) return;
    setBusy(true);
    setError(null);
    setImportResult(null);
    try {
      const formData = new FormData();
      formData.set("file", file);
      formData.set("confirmation", confirmation);
      const response = await fetch("/api/internal/production-migration-import", { method: "POST", body: formData });
      const body = await response.json();
      if (!response.ok) {
        setError(body.error ?? "A production import nem futott le.");
        return;
      }
      setImportResult(body.reconciliation as Record<string, unknown>);
    } catch {
      setError("A production import technikai hiba miatt nem futott le.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <form onSubmit={submit} className="card stack">
        <h2>AllBooked CSV dry-run</h2>
        <p className="muted">Csak ellenőrzés: nem ír adatbázisba, nem hoz létre felhasználót vagy foglalást, és nem küld e-mailt.</p>
        <label>Booking export CSV<input name="file" type="file" accept=".csv,text/csv" required onChange={(event) => setFile(event.target.files?.[0] ?? null)} /></label>
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

      {result?.valid && result.summary.normalizedUsers === 1 && result.summary.normalizedBookings === 21 ? <section className="card stack">
        <div><p className="eyebrow">Production író import</p><h2>21 foglalás atomi betöltése</h2></div>
        <p className="muted">Csak a production Supabase cél engedélyezett. Az import `individual` foglalásokat és a Forrás tér csoportjogot hozza létre; legacy árat és payment státuszt nem vesz át, e-mailt nem küld.</p>
        <label>Megerősítés<input value={confirmation} onChange={(event) => setConfirmation(event.target.value)} placeholder={IMPORT_CONFIRMATION} autoComplete="off" /></label>
        <button type="button" className="danger" disabled={busy || !file || confirmation !== IMPORT_CONFIRMATION} onClick={runImport}>
          {busy ? "Import és reconciliation folyamatban…" : "Import stagingre"}
        </button>
      </section> : null}

      {importResult ? <section className="card stack">
        <div><p className="eyebrow">Import utáni reconciliation</p><h2>{importResult.valid === true ? "PASS" : "FAIL"}</h2></div>
        <div className="admin-grid">
          <p><strong>Felhasználó:</strong> {String(importResult.email ?? "—")}</p>
          <p><strong>Telefon:</strong> {String(importResult.phone ?? "—")}</p>
          <p><strong>Jogosultság:</strong> {String(importResult.accessGroup ?? "—")}</p>
          <p><strong>Foglalások:</strong> {String(importResult.bookings ?? "—")}</p>
          <p><strong>60 / 90 perc:</strong> {String(importResult.duration60 ?? "—")} / {String(importResult.duration90 ?? "—")}</p>
          <p><strong>Összes perc:</strong> {String(importResult.totalMinutes ?? "—")}</p>
          <p><strong>Dátumtartomány:</strong> {String(importResult.firstServiceDate ?? "—")} – {String(importResult.lastServiceDate ?? "—")}</p>
          <p><strong>Legacy pénzügyi rekord:</strong> {Number(importResult.legacyPriceOverrides ?? 0) + Number(importResult.settlements ?? 0) + Number(importResult.settlementLines ?? 0) + Number(importResult.payments ?? 0)}</p>
        </div>
        <p className="message success" role="status">A tranzakció és a tételes adatbázis-reconciliation sikeres.</p>
      </section> : null}
    </div>
  );
}
