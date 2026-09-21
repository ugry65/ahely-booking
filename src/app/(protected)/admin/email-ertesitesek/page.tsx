import { requireAdmin } from "@/lib/auth";
import {
  bookingEmailEventLabel,
  bookingEmailMonitorAlerts,
  bookingEmailRunStatusLabel,
  bookingEmailScopeLabel,
  bookingEmailTimestamp,
  count,
  type BookingEmailMonitorSummary,
  type BookingEmailProblemItem,
  type BookingEmailWorkerRun,
} from "@/lib/booking-email/monitor";
import { createClient } from "@/lib/supabase/server";
import { runBookingEmailCapture } from "./actions";

function problemLabel(value: BookingEmailProblemItem["problem_kind"]): string {
  return ({
    dead_letter: "Végleg sikertelen",
    stale_sending: "Lejárt lease",
    retry: "Újrapróbálás",
  })[value];
}

function runCounts(run: BookingEmailWorkerRun): string {
  if (run.status !== "success") return "–";
  return `${run.claimed_count} / ${run.sent_count} / ${run.captured_count} / ${run.retry_count} / ${run.dead_letter_count}`;
}

export default async function BookingEmailMonitorPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const [summaryResponse, problemsResponse, runsResponse] = await Promise.all([
    supabase.rpc("admin_booking_email_monitor").returns<BookingEmailMonitorSummary[]>(),
    supabase.rpc("admin_booking_email_problem_items", { p_limit: 50 }).returns<BookingEmailProblemItem[]>(),
    supabase.rpc("admin_booking_email_worker_runs", { p_limit: 20 }).returns<BookingEmailWorkerRun[]>(),
  ]);
  const summaries = (summaryResponse.data ?? []) as unknown as BookingEmailMonitorSummary[];
  const problems = (problemsResponse.data ?? []) as unknown as BookingEmailProblemItem[];
  const runs = (runsResponse.data ?? []) as unknown as BookingEmailWorkerRun[];
  const summary = summaries[0] ?? null;
  const alerts = summary ? bookingEmailMonitorAlerts(summary) : [];

  return <section className="stack email-monitor">
    <header className="page-heading">
      <div>
        <p className="eyebrow">Adminisztráció</p>
        <h1>E-mail kézbesítés</h1>
        <p className="muted">Foglalási értesítések biztonságos állapot- és worker heartbeat monitorja.</p>
      </div>
    </header>

    <p className="message">Ez a nézet csak összesített állapotot és biztonságos hibaleírást mutat. Címzett, levéltörzs, SMTP-jelszó és nyers szolgáltatói válasz nem jelenik meg. Kézi újraküldés még nincs engedélyezve.</p>

    {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
    {params.uzenet ? <p className="message success" role="status">{params.uzenet}</p> : null}

    {process.env.BOOKING_EMAIL_MODE?.trim() === "capture" ? <section className="card wide-card stack">
      <div><p className="eyebrow">Staging UAT</p><h2>Capture feldolgozás</h2><p className="muted">A függő értesítéseket rendereli és auditáltan capture állapotban lezárja. SMTP-kapcsolatot nem nyit és valódi levelet nem küld.</p></div>
      <form action={runBookingEmailCapture}>
        <button type="submit">Capture feldolgozás indítása</button>
      </form>
    </section> : null}

    {summaryResponse.error ? <p className="message error" role="alert">Az e-mail-kézbesítési összesítő betöltése nem sikerült.</p> : null}
    {problemsResponse.error ? <p className="message error" role="alert">A problémalista betöltése nem sikerült.</p> : null}
    {runsResponse.error ? <p className="message error" role="alert">A worker-futások betöltése nem sikerült.</p> : null}

    {summary ? <>
      {alerts.length ? <section className="stack" aria-label="Kézbesítési figyelmeztetések">
        {alerts.map((alert) => <p className={`message ${alert.severity === "error" ? "error" : "warning"}`} role="alert" key={alert.text}>{alert.text}</p>)}
      </section> : <p className="message success">A monitor jelenleg nem jelez kézbesítési hibát vagy elmaradt heartbeatot.</p>}

      <section className="email-monitor-grid" aria-label="Kézbesítési összesítő">
        <article className="card email-monitor-metric"><span className="muted">Esedékes most</span><strong>{count(summary.due_count)}</strong><small>pending + retry</small></article>
        <article className="card email-monitor-metric"><span className="muted">Végleg sikertelen</span><strong>{count(summary.dead_letter_count)}</strong><small>vizsgálatot igényel</small></article>
        <article className="card email-monitor-metric"><span className="muted">Elküldve 24 órán belül</span><strong>{count(summary.sent_24h_count)}</strong><small>összesen {count(summary.sent_count)}</small></article>
        <article className="card email-monitor-metric"><span className="muted">Capture összesen</span><strong>{count(summary.captured_count)}</strong><small>SMTP-küldés nélkül</small></article>
      </section>

      <section className="card wide-card email-monitor-status stack">
        <div><p className="eyebrow">Heartbeat</p><h2>Worker állapot</h2></div>
        <dl>
          <div><dt>Utolsó worker indítás</dt><dd>{bookingEmailTimestamp(summary.last_worker_started_at)}</dd></div>
          <div><dt>Utolsó sikeres futás</dt><dd>{bookingEmailTimestamp(summary.last_worker_success_at)}</dd></div>
          <div><dt>Utolsó hibás futás</dt><dd>{bookingEmailTimestamp(summary.last_worker_failure_at)}</dd></div>
          <div><dt>Utolsó SMTP-küldés</dt><dd>{bookingEmailTimestamp(summary.last_sent_at)}</dd></div>
          <div><dt>Feldolgozás alatt</dt><dd>{count(summary.sending_count)}</dd></div>
          <div><dt>Retry állapot</dt><dd>{count(summary.retry_count)}</dd></div>
          <div><dt>Legrégebbi esedékes</dt><dd>{bookingEmailTimestamp(summary.oldest_due_at)}</dd></div>
          <div><dt>SMTP auth hiba / 24 óra</dt><dd>{count(summary.smtp_auth_error_24h_count)}</dd></div>
        </dl>
      </section>
    </> : null}

    <section className="card wide-card stack">
      <div><p className="eyebrow">Ellenőrzés</p><h2>Aktuális problémák</h2><p className="muted">Csak retry, végleg sikertelen és lejárt lease állapotok. Az outbox-azonosító auditcélú, nem tartalmaz foglalási adatot.</p></div>
      <div className="table-scroll"><table className="email-monitor-table">
        <thead><tr><th>Állapot</th><th>Esemény</th><th>Hatókör</th><th>Próbák</th><th>Következő / lease</th><th>Biztonságos hiba</th><th>Outbox ID</th></tr></thead>
        <tbody>{problems.map((problem) => <tr key={problem.outbox_id}>
          <td data-label="Állapot">{problemLabel(problem.problem_kind)}</td>
          <td data-label="Esemény">{bookingEmailEventLabel(problem.event_type)}</td>
          <td data-label="Hatókör">{bookingEmailScopeLabel(problem.scope)}</td>
          <td data-label="Próbák">{problem.attempts}</td>
          <td data-label="Következő / lease">{bookingEmailTimestamp(problem.problem_kind === "stale_sending" ? problem.lease_expires_at : problem.next_attempt_at)}</td>
          <td data-label="Biztonságos hiba">{problem.last_error_safe ?? problem.last_error_code ?? "–"}</td>
          <td data-label="Outbox ID"><code>{problem.outbox_id}</code></td>
        </tr>)}</tbody>
      </table></div>
      {!problems.length && !problemsResponse.error ? <p className="muted">Nincs retry, végleg sikertelen vagy lejárt lease állapotú e-mail.</p> : null}
    </section>

    <section className="card wide-card stack">
      <div><p className="eyebrow">Audit</p><h2>Legutóbbi worker-futások</h2><p className="muted">Darabszámok: claimelt / elküldött / capture / retry / dead letter.</p></div>
      <div className="table-scroll"><table className="email-monitor-table">
        <thead><tr><th>Indult</th><th>Befejeződött</th><th>Mód</th><th>Állapot</th><th>Darabszámok</th><th>Biztonságos hiba</th></tr></thead>
        <tbody>{runs.map((run) => <tr key={run.run_id}>
          <td data-label="Indult">{bookingEmailTimestamp(run.started_at)}</td>
          <td data-label="Befejeződött">{bookingEmailTimestamp(run.finished_at)}</td>
          <td data-label="Mód">{run.mode}</td>
          <td data-label="Állapot">{bookingEmailRunStatusLabel(run.status)}</td>
          <td data-label="Darabszámok">{runCounts(run)}</td>
          <td data-label="Biztonságos hiba">{run.error_safe ?? run.error_code ?? "–"}</td>
        </tr>)}</tbody>
      </table></div>
      {!runs.length && !runsResponse.error ? <p className="muted">Még nincs auditált worker-futás. Disabled módban ez szándékos.</p> : null}
    </section>
  </section>;
}
