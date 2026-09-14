"use client";

import { FormEvent, useState } from "react";

type BookingUseType = "individual" | "group";

type DryRunBooking = {
  line: number;
  holderEmail: string;
  roomSource: string;
  roomTarget: string;
  startLocal: string;
  endLocal: string;
  durationMinutes: number;
  bookingTitle: string | null;
  sourceFingerprint: string;
};

type DryRunResult = {
  valid: boolean;
  ignoredPricingFields: string[];
  issues: { line: number; code: string; message: string }[];
  users: { email: string; firstName: string; lastName: string; phone: string | null; accessTags: string[] }[];
  bookings: DryRunBooking[];
  summary: {
    sourceRows: number;
    normalizedUsers: number;
    normalizedBookings: number;
    totalMinutes: number;
    totalHours: number;
    bookingsByRoom: Record<string, number>;
    bookingsByUser: Record<string, number>;
  };
  importApproval: {
    valid: boolean;
    issues: string[];
    user: DryRunResult["users"][number] | null;
    requiredAccessGroups: string[];
    trainingBookings: DryRunBooking[];
    confirmation: string | null;
  };
};

export function MigrationDryRunForm() {
  const [result, setResult] = useState<DryRunResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [confirmation, setConfirmation] = useState("");
  const [trainingUseTypes, setTrainingUseTypes] = useState<Record<string, BookingUseType>>({});
  const [importResult, setImportResult] = useState<Record<string, unknown> | null>(null);
  const [cleanupConfirmation, setCleanupConfirmation] = useState("");
  const [cleanupResult, setCleanupResult] = useState<Record<string, unknown> | null>(null);
  const [busy, setBusy] = useState(false);

  function selectFile(nextFile: File | null) {
    setFile(nextFile);
    setResult(null);
    setError(null);
    setConfirmation("");
    setTrainingUseTypes({});
    setImportResult(null);
  }

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

  const trainingComplete = result?.importApproval.trainingBookings.every(
    (booking) => trainingUseTypes[booking.sourceFingerprint],
  ) ?? false;
  const expectedConfirmation = result?.importApproval.confirmation ?? "";

  async function runImport() {
    if (!file || !result?.importApproval.valid || confirmation !== expectedConfirmation || !trainingComplete) return;
    setBusy(true);
    setError(null);
    setImportResult(null);
    try {
      const formData = new FormData();
      formData.set("file", file);
      formData.set("confirmation", confirmation);
      formData.set("trainingUseTypes", JSON.stringify(trainingUseTypes));
      const response = await fetch("/api/internal/production-customer-migration-import", { method: "POST", body: formData });
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

  async function voidPappDalmaTrial() {
    if (cleanupConfirmation !== "REMOVE-PAPP-DALMA-TEST-DATA") return;
    setBusy(true);
    setError(null);
    setCleanupResult(null);
    try {
      const response = await fetch("/api/internal/void-papp-dalma-test-import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ confirmation: cleanupConfirmation }),
      });
      const body = await response.json();
      if (!response.ok) {
        setError(body.error ?? "A próbaadatok visszavonása nem sikerült.");
        return;
      }
      setCleanupResult(body.reconciliation as Record<string, unknown>);
    } catch {
      setError("A próbaadatok visszavonása technikai hiba miatt nem sikerült.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <form onSubmit={submit} className="card stack">
        <h2>Egy ügyfél AllBooked CSV-jének ellenőrzése</h2>
        <p className="muted">Egy fájl pontosan egy ügyfél foglalásait tartalmazza. A dry-run nem ír adatbázisba és nem küld e-mailt.</p>
        <label>
          Booking export CSV
          <input name="file" type="file" accept=".csv,text/csv" required onChange={(event) => selectFile(event.target.files?.[0] ?? null)} />
        </label>
        <button type="submit" disabled={busy}>{busy ? "Ellenőrzés folyamatban…" : "Dry-run futtatása"}</button>
      </form>

      {error ? <p className="message error" role="alert">{error}</p> : null}
      {result ? <section className="card stack">
        <div><p className="eyebrow">Dry-run eredmény</p><h2>{result.importApproval.valid ? "PASS" : "ELLENŐRZÉST IGÉNYEL"}</h2></div>
        <div className="admin-grid">
          <p><strong>Ügyfél:</strong> {result.importApproval.user ? `${result.importApproval.user.lastName} ${result.importApproval.user.firstName}` : "—"}</p>
          <p><strong>E-mail:</strong> {result.importApproval.user?.email ?? "—"}</p>
          <p><strong>Foglalások:</strong> {result.summary.normalizedBookings}</p>
          <p><strong>Összes óra:</strong> {result.summary.totalHours}</p>
        </div>
        <div><h3>Automatikusan szükséges helyiségcsoportok</h3><p>{result.importApproval.requiredAccessGroups.join(", ") || "—"}</p></div>
        <div><h3>Foglalások helyiségenként</h3>{Object.entries(result.summary.bookingsByRoom).map(([room, count]) => <p key={room}>{room}: {count} db</p>)}</div>
        <div><h3>Nem migrált legacy pénzügyi mezők</h3><p className="muted">{result.ignoredPricingFields.join(", ")}</p></div>
        {result.issues.length || result.importApproval.issues.length ? <div><h3>Blokkoló eltérések</h3><ul>
          {result.issues.map((issue, index) => <li key={`${issue.line}-${issue.code}-${index}`}>{issue.line}. sor – {issue.message}</li>)}
          {result.importApproval.issues.map((issue, index) => <li key={`approval-${index}`}>{issue}</li>)}
        </ul></div> : <p className="message success" role="status">A fájl egy ügyfél kontrollált importjára alkalmas.</p>}
      </section> : null}

      {result?.importApproval.valid && result.importApproval.trainingBookings.length ? <section className="card stack">
        <div><p className="eyebrow">Kötelező kézi besorolás</p><h2>Tréningterem-foglalások</h2></div>
        <p className="muted">Az exportból nem állapítható meg biztonságosan, hogy a Tréningterem foglalása egyéni vagy csoportos volt. Minden sort sorolj be.</p>
        <div className="table-scroll">
          <table>
            <thead><tr><th>Dátum</th><th>Idő</th><th>Megnevezés</th><th>Típus</th></tr></thead>
            <tbody>{result.importApproval.trainingBookings.map((booking) => <tr key={booking.sourceFingerprint}>
              <td>{booking.startLocal.slice(0, 10)}</td>
              <td>{booking.startLocal.slice(11)}–{booking.endLocal.slice(11)}</td>
              <td>{booking.bookingTitle ?? "—"}</td>
              <td><select aria-label={`${booking.startLocal} foglalástípusa`} value={trainingUseTypes[booking.sourceFingerprint] ?? ""} onChange={(event) => setTrainingUseTypes((current) => ({ ...current, [booking.sourceFingerprint]: event.target.value as BookingUseType }))}>
                <option value="">Válassz…</option><option value="individual">Egyéni</option><option value="group">Csoportos</option>
              </select></td>
            </tr>)}</tbody>
          </table>
        </div>
      </section> : null}

      {result?.importApproval.valid ? <section className="card stack">
        <div><p className="eyebrow">Production író import</p><h2>Ügyfél és foglalások atomi betöltése</h2></div>
        <p className="muted">A művelet létrehozza vagy ellenőrzi a felhasználót, kiosztja a szükséges helyiségcsoportokat és betölti a foglalásokat. Árat, fizetési státuszt és megjegyzést nem migrál, e-mailt nem küld.</p>
        <label>Megerősítés<input value={confirmation} onChange={(event) => setConfirmation(event.target.value)} placeholder={expectedConfirmation} autoComplete="off" /></label>
        <button type="button" className="danger" disabled={busy || !file || confirmation !== expectedConfirmation || !trainingComplete} onClick={runImport}>
          {busy ? "Import és reconciliation folyamatban…" : "Import productionre"}
        </button>
      </section> : null}

      {importResult ? <section className="card stack">
        <div><p className="eyebrow">Import utáni reconciliation</p><h2>{importResult.valid === true ? "PASS" : "FAIL"}</h2></div>
        <div className="admin-grid">
          <p><strong>Felhasználó:</strong> {String(importResult.email ?? "—")}</p>
          <p><strong>Helyiségcsoportok:</strong> {Array.isArray(importResult.accessGroups) ? importResult.accessGroups.join(", ") : "—"}</p>
          <p><strong>Foglalások:</strong> {String(importResult.bookings ?? "—")}</p>
          <p><strong>Új / meglévő:</strong> {String(importResult.created ?? "—")} / {String(importResult.existing ?? "—")}</p>
          <p><strong>Összes perc:</strong> {String(importResult.totalMinutes ?? "—")}</p>
          <p><strong>Dátumtartomány:</strong> {String(importResult.firstServiceDate ?? "—")} – {String(importResult.lastServiceDate ?? "—")}</p>
          <p><strong>Tréning egyéni / csoportos:</strong> {String(importResult.trainingIndividual ?? 0)} / {String(importResult.trainingGroup ?? 0)}</p>
          <p><strong>Legacy pénzügyi rekord:</strong> {String(importResult.legacyFinancialRows ?? 0)}</p>
        </div>
        <p className="message success" role="status">A tranzakció és a tételes adatbázis-reconciliation sikeres. Az aktiváló e-mail külön, a Felhasználók oldalon küldhető.</p>
      </section> : null}

      <section className="card stack">
        <div><p className="eyebrow">Egyszeri indulási művelet</p><h2>Papp Dalma próbaimport visszavonása</h2></div>
        <p className="muted">Kizárólag a bizonyított 21 foglalásos próbaimportot teszi üzletileg láthatatlanná, eltávolítja a próba-jogosultságot és inaktiválja a profilt. Az auditbizonyíték megmarad, a valódi ügyfél később friss CSV-ből újramigrálható.</p>
        <label>Megerősítés<input value={cleanupConfirmation} onChange={(event) => setCleanupConfirmation(event.target.value)} placeholder="REMOVE-PAPP-DALMA-TEST-DATA" autoComplete="off" /></label>
        <button type="button" className="danger-button" disabled={busy || cleanupConfirmation !== "REMOVE-PAPP-DALMA-TEST-DATA"} onClick={voidPappDalmaTrial}>
          {busy ? "Visszavonás és ellenőrzés folyamatban…" : "Papp Dalma próbaadat visszavonása"}
        </button>
        {cleanupResult ? <p className="message success" role="status">PASS: {String(cleanupResult.voidedBookings ?? 0)} próba-foglalás kivezetve, aktív foglalás: {String(cleanupResult.activeBookings ?? "—")}. A profil valódi újraimportra kész.</p> : null}
      </section>
    </div>
  );
}
