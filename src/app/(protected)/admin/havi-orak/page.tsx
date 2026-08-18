import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { monthStart, type MonthlyHoursRow, validMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

function currentBudapestMonth() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
}

export default async function MonthlyHoursPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const month = params.honap && validMonth(params.honap) ? params.honap : currentBudapestMonth();
  const supabase = await createClient();
  const response = await supabase.rpc("admin_monthly_booking_hours", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
  const rows = (response.data ?? []) as unknown as MonthlyHoursRow[];
  const totalMinutes = rows.reduce((sum, row) => sum + Number(row.total_minutes), 0);

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Havi óraszám</h1><p className="muted">Felhasználónkénti foglalási idő, díj- és pénzügyi számítás nélkül.</p></div><Link className="button secondary" href="/admin/hozzaferesek">Hozzáférések</Link></header>
    <form className="card monthly-filter" method="get"><label>Elszámolási hónap<input type="month" name="honap" defaultValue={month} required /></label><button>Megjelenítés</button><a className="button secondary" href={`/admin/havi-orak/export?honap=${month}`}>CSV letöltése</a></form>
    {response.error ? <p className="message error" role="alert">A havi óraszám betöltése nem sikerült.</p> : null}
    <section className="card wide-card stack"><h2>{month} összesítés</h2><div className="table-scroll"><table><thead><tr><th>Felhasználó</th><th>E-mail</th><th>Foglalások</th><th>Összes perc</th><th>Összes óra</th></tr></thead><tbody>{rows.map((row) => <tr key={row.user_id}><td>{row.user_name}</td><td>{row.email}</td><td>{row.booking_count}</td><td>{row.total_minutes}</td><td>{Number(row.total_hours).toFixed(2)}</td></tr>)}</tbody><tfoot><tr><th colSpan={3}>Mindösszesen</th><th>{totalMinutes}</th><th>{(totalMinutes / 60).toFixed(2)}</th></tr></tfoot></table></div>{rows.length ? null : <p className="muted">Ebben a hónapban nincs elszámolható aktív foglalás.</p>}</section>
  </section>;
}
