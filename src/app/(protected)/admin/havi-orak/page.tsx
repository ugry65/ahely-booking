import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { monthStart, selectedMonths, type MonthlyBookingDetail, type MonthlyBookingDetailWithMonth, type MonthlyHoursRow, type MonthlyHoursWithMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";
import { MonthMultiSelect } from "./month-multi-select";

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
  const months = selectedMonths(params.honapok ?? params.honap, currentBudapestMonth());
  const supabase = await createClient();

  const rows: MonthlyHoursWithMonth[] = [];
  let summaryError = false;
  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_booking_hours", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
    if (response.error) summaryError = true;
    for (const row of (response.data ?? []) as unknown as MonthlyHoursRow[]) rows.push({ ...row, month });
  }

  const users = Array.from(new Map(rows.map((row) => [row.user_id, row.user_name])).entries())
    .map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name, "hu"));
  const selectedUserId = params.user && users.some((user) => user.id === params.user) ? params.user : null;

  const details: MonthlyBookingDetailWithMonth[] = [];
  let detailsError = false;
  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_active_booking_details", {
      p_month: monthStart(month)!, p_user_id: selectedUserId,
    }).returns<MonthlyBookingDetail[]>();
    if (response.error) detailsError = true;
    for (const row of (response.data ?? []) as unknown as MonthlyBookingDetail[]) details.push({ ...row, month });
  }

  const totalHours = rows.reduce((sum, row) => sum + Number(row.total_hours), 0);
  const monthQuery = months.join(",");
  const detailExportQuery = new URLSearchParams({ honapok: monthQuery });
  if (selectedUserId) detailExportQuery.set("user", selectedUserId);

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Havi órák</h1><p className="muted">Számlázási és elszámolási alap. Kizárólag az aktív, le nem mondott foglalások szerepelnek benne.</p></div><Link className="button secondary" href="/admin/lemondasok">Lemondások</Link></header>

    <form className="card stack" method="get">
      <MonthMultiSelect initialMonths={months} />
      <div className="monthly-filter"><button>Megjelenítés</button><a className="button secondary" href={`/admin/havi-orak/export?honapok=${encodeURIComponent(monthQuery)}`}>Összesítő CSV</a></div>
    </form>

    {summaryError ? <p className="message error" role="alert">A havi óraszám betöltése nem sikerült teljes körűen. Az adatokat ne használd elszámolásra, amíg a hiba fennáll.</p> : null}
    <section className="card wide-card stack">
      <h2>Elszámolási összesítés</h2>
      <p className="muted">A hónap külön oszlop, ezért több kijelölt hónap adatai sem keverednek össze. Lemondott foglalás nem szerepelhet.</p>
      <div className="table-scroll"><table>
        <thead><tr><th>Hónap</th><th>Felhasználó</th><th>Összes óra</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={`${row.month}-${row.user_id}`}><td>{row.month}</td><td>{row.user_name}</td><td>{hours(row.total_hours)}</td></tr>)}</tbody>
        <tfoot><tr><th colSpan={2}>Kijelölt hónapok mindösszesen</th><th>{hours(totalHours)}</th></tr></tfoot>
      </table></div>
      {rows.length ? null : <p className="muted">A kijelölt hónapokban nincs elszámolható aktív foglalás.</p>}
    </section>

    <section className="card wide-card stack">
      <div><p className="eyebrow">Ellenőrzés</p><h2>Tételes aktív foglalások</h2><p className="muted">Minden elszámolt foglalás visszaellenőrizhető. A lista ugyanazokat a kijelölt hónapokat használja; lemondott foglalás nem szerepelhet.</p></div>
      <form method="get" className="monthly-filter">
        <input type="hidden" name="honapok" value={monthQuery} />
        <label>Felhasználó<select name="user" defaultValue={selectedUserId ?? ""}><option value="">Összes felhasználó</option>{users.map((user) => <option key={user.id} value={user.id}>{user.name}</option>)}</select></label>
        <button>Részletek</button>
        <a className="button secondary" href={`/admin/havi-orak/reszletek-export?${detailExportQuery.toString()}`}>Részletes CSV</a>
      </form>
      {detailsError ? <p className="message error" role="alert">A tételes foglalások betöltése nem sikerült teljes körűen. Az adatokat ne használd ellenőrzésre, amíg a hiba fennáll.</p> : null}
      <div className="table-scroll"><table>
        <thead><tr><th>Hónap</th><th>Felhasználó</th><th>Dátum</th><th>Helyiség</th><th>Mettől</th><th>Meddig</th><th>Óra</th></tr></thead>
        <tbody>{details.map((row) => <tr key={row.booking_id}><td>{row.month}</td><td>{row.user_name}</td><td>{row.booking_date}</td><td>{row.room_name}</td><td>{time(row.start_time)}</td><td>{time(row.end_time)}</td><td>{hours(row.total_hours)}</td></tr>)}</tbody>
      </table></div>
      {!details.length && !detailsError ? <p className="muted">A kiválasztott feltételekkel nincs aktív foglalás.</p> : null}
    </section>
  </section>;
}
