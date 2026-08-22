import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { cancellationPeriod, CANCELLATION_PERIODS, leadTimeLabel, type CancellationDetailRow, type CancellationSummaryRow } from "@/lib/cancellation-report";
import { monthStart, validMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

function currentBudapestMonth() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
}
function hours(value: number | string) {
  return Number(value).toLocaleString("hu-HU", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function time(value: string) { return value.slice(0, 5); }
function cancellationTimestamp(value: string) {
  return new Intl.DateTimeFormat("hu-HU", {
    timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
  }).format(new Date(value));
}

export default async function CancellationsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const endMonth = params.honap && validMonth(params.honap) ? params.honap : currentBudapestMonth();
  const period = cancellationPeriod(params.idoszak);
  const supabase = await createClient();
  const summaryResponse = await supabase.rpc("admin_cancellation_summary", {
    p_end_month: monthStart(endMonth)!, p_months: period,
  }).returns<CancellationSummaryRow[]>();
  const rows = (summaryResponse.data ?? []) as unknown as CancellationSummaryRow[];
  const selectedUserId = params.user && rows.some((row) => row.user_id === params.user) ? params.user : null;
  const detailsResponse = await supabase.rpc("admin_cancellation_details", {
    p_end_month: monthStart(endMonth)!, p_months: period, p_user_id: selectedUserId,
  }).returns<CancellationDetailRow[]>();
  const details = (detailsResponse.data ?? []) as unknown as CancellationDetailRow[];
  const detailExportQuery = new URLSearchParams({ honap: endMonth, idoszak: String(period) });
  if (selectedUserId) detailExportQuery.set("user", selectedUserId);

  return <section className="stack">
    <header className="page-heading">
      <div><p className="eyebrow">Adminisztráció</p><h1>Lemondások</h1><p className="muted">A lemondási viselkedés külön riportja. Ezek az adatok nem részei a számlázási havi óráknak.</p></div>
      <Link className="button secondary" href="/admin/havi-orak">Havi órák</Link>
    </header>

    <form className="card monthly-filter" method="get">
      <label>Záró hónap<input type="month" name="honap" defaultValue={endMonth} required /></label>
      <label>Időszak<select name="idoszak" defaultValue={String(period)}>{CANCELLATION_PERIODS.map((months) => <option key={months} value={months}>{months} hónap</option>)}</select></label>
      <button>Megjelenítés</button>
      <a className="button secondary" href={`/admin/lemondasok/export?honap=${endMonth}&idoszak=${period}`}>Összesítő CSV</a>
    </form>

    {summaryResponse.error ? <p className="message error" role="alert">A lemondási statisztika betöltése nem sikerült.</p> : null}
    <section className="card wide-card stack">
      <div><h2>Userenkénti lemondási statisztika</h2><p className="muted">A „lemondási arány” csak azt méri, amikor a foglalást maga a user mondta le. Admin által törölt foglalás nem növeli ezt az arányt. A „törölt foglalás/óra” viszont minden lemondott foglalást megmutat.</p></div>
      <div className="table-scroll"><table>
        <thead><tr><th>Felhasználó</th><th>Összes foglalás</th><th>Törölt foglalás</th><th>Törölt óra</th><th>User saját törlése</th><th>Lemondási arány</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={row.user_id}><td>{row.user_name}</td><td>{row.total_bookings}</td><td>{row.cancelled_count}</td><td>{hours(row.cancelled_hours)}</td><td>{row.user_cancelled_count}</td><td>{Number(row.cancellation_rate).toLocaleString("hu-HU", { maximumFractionDigits: 1 })}%</td></tr>)}</tbody>
      </table></div>
      {!rows.length && !summaryResponse.error ? <p className="muted">A kiválasztott időszakban nincs foglalási adat.</p> : null}
    </section>

    <section className="card wide-card stack">
      <div><p className="eyebrow">Ellenőrzés</p><h2>Tételes lemondások</h2><p className="muted">Az eredeti foglalási idő, a lemondás időpontja, az előzetes időtáv és a lemondó személy is visszakereshető.</p></div>
      <form method="get" className="monthly-filter">
        <input type="hidden" name="honap" value={endMonth} />
        <input type="hidden" name="idoszak" value={period} />
        <label>Felhasználó<select name="user" defaultValue={selectedUserId ?? ""}><option value="">Összes felhasználó</option>{rows.map((row) => <option key={row.user_id} value={row.user_id}>{row.user_name}</option>)}</select></label>
        <button>Részletek</button>
        <a className="button secondary" href={`/admin/lemondasok/reszletek-export?${detailExportQuery.toString()}`}>Részletes CSV</a>
      </form>
      {detailsResponse.error ? <p className="message error" role="alert">A tételes lemondások betöltése nem sikerült.</p> : null}
      <div className="table-scroll"><table>
        <thead><tr><th>Felhasználó</th><th>Dátum</th><th>Helyiség</th><th>Mettől</th><th>Meddig</th><th>Óra</th><th>Lemondás ideje</th><th>Mennyivel előtte</th><th>Lemondta</th><th>Indok</th></tr></thead>
        <tbody>{details.map((row) => <tr key={row.booking_id}><td>{row.user_name}</td><td>{row.booking_date}</td><td>{row.room_name}</td><td>{time(row.start_time)}</td><td>{time(row.end_time)}</td><td>{hours(row.cancelled_hours)}</td><td>{cancellationTimestamp(row.cancelled_at)}</td><td>{leadTimeLabel(row.minutes_before_start)}</td><td>{row.cancelled_by_user ? `${row.cancelled_by_name} (user)` : `${row.cancelled_by_name} (admin)`}</td><td>{row.cancellation_reason ?? "–"}</td></tr>)}</tbody>
      </table></div>
      {!details.length && !detailsResponse.error ? <p className="muted">A kiválasztott feltételekkel nincs lemondott foglalás.</p> : null}
    </section>
  </section>;
}
