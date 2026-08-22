import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { monthStart, type MonthlyBookingDetail, type MonthlyHoursRow, validMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

function currentBudapestMonth() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
}
function hours(value: number | string) {
  return Number(value).toLocaleString("hu-HU", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function time(value: string) { return value.slice(0, 5); }

export default async function MonthlyHoursPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const month = params.honap && validMonth(params.honap) ? params.honap : currentBudapestMonth();
  const supabase = await createClient();
  const response = await supabase.rpc("admin_monthly_booking_hours", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
  const rows = (response.data ?? []) as unknown as MonthlyHoursRow[];
  const selectedUserId = params.user && rows.some((row) => row.user_id === params.user) ? params.user : null;
  const detailsResponse = await supabase.rpc("admin_monthly_active_booking_details", {
    p_month: monthStart(month)!, p_user_id: selectedUserId,
  }).returns<MonthlyBookingDetail[]>();
  const details = (detailsResponse.data ?? []) as unknown as MonthlyBookingDetail[];
  const totalHours = rows.reduce((sum, row) => sum + Number(row.total_hours), 0);

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Havi órák</h1><p className="muted">Számlázási és elszámolási alap. Kizárólag az aktív, le nem mondott foglalások szerepelnek benne.</p></div><Link className="button secondary" href="/admin/lemondasok">Lemondások</Link></header>

    <form className="card monthly-filter" method="get">
      <label>Elszámolási hónap<input type="month" name="honap" defaultValue={month} required /></label>
      <button>Megjelenítés</button>
      <a className="button secondary" href={`/admin/havi-orak/export?honap=${month}`}>CSV letöltése</a>
    </form>

    {response.error ? <p className="message error" role="alert">A havi óraszám betöltése nem sikerült.</p> : null}
    <section className="card wide-card stack">
      <h2>{month} összesítés</h2>
      <p className="muted">Az összesítőből szándékosan kimarad a foglalások darabszáma és a percérték: az elszámolási adat a felhasználó és a foglalt órák száma.</p>
      <div className="table-scroll"><table>
        <thead><tr><th>Felhasználó</th><th>Összes óra</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={row.user_id}><td>{row.user_name}</td><td>{hours(row.total_hours)}</td></tr>)}</tbody>
        <tfoot><tr><th>Mindösszesen</th><th>{hours(totalHours)}</th></tr></tfoot>
      </table></div>
      {rows.length ? null : <p className="muted">Ebben a hónapban nincs elszámolható aktív foglalás.</p>}
    </section>

    <section className="card wide-card stack">
      <div><p className="eyebrow">Ellenőrzés</p><h2>Tételes aktív foglalások</h2><p className="muted">Ha egy havi összesítés vitatott, itt minden elszámolt foglalás visszaellenőrizhető. Lemondott foglalás ezen a listán nem szerepelhet.</p></div>
      <form method="get" className="monthly-filter">
        <input type="hidden" name="honap" value={month} />
        <label>Felhasználó<select name="user" defaultValue={selectedUserId ?? ""}><option value="">Összes felhasználó</option>{rows.map((row) => <option key={row.user_id} value={row.user_id}>{row.user_name}</option>)}</select></label>
        <button>Részletek</button>
      </form>
      {detailsResponse.error ? <p className="message error" role="alert">A tételes foglalások betöltése nem sikerült.</p> : null}
      <div className="table-scroll"><table>
        <thead><tr><th>Felhasználó</th><th>Dátum</th><th>Helyiség</th><th>Mettől</th><th>Meddig</th><th>Óra</th></tr></thead>
        <tbody>{details.map((row) => <tr key={row.booking_id}><td>{row.user_name}</td><td>{row.booking_date}</td><td>{row.room_name}</td><td>{time(row.start_time)}</td><td>{time(row.end_time)}</td><td>{hours(row.total_hours)}</td></tr>)}</tbody>
      </table></div>
      {!details.length && !detailsResponse.error ? <p className="muted">A kiválasztott feltételekkel nincs aktív foglalás.</p> : null}
    </section>
  </section>;
}
