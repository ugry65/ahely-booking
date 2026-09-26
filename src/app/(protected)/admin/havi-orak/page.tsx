import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { monthStart, selectedMonths, mergeBookingTitles, type MonthlyActiveBookingTitle, type MonthlyBookingDetail, type MonthlyBookingDetailWithMonth, type MonthlyHoursRow, type MonthlyHoursWithMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";
import { MonthMultiSelect } from "./month-multi-select";
import { correctHistoricalBookingRate, createSettlementRevision } from "./actions";

function currentBudapestMonth() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
}
function hours(value: number | string) {
  return Number(value).toLocaleString("hu-HU", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function time(value: string) { return value.slice(0, 5); }
function huf(value: number | string) { return Number(value).toLocaleString("hu-HU") + " Ft"; }
const rateSourceLabel = { booking_override: "Foglalási egyedi", user_override: "User egyedi", central_tier: "Központi sáv", training_room: "Tréningterem" } as const;

export default async function MonthlyHoursPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const months = selectedMonths(params.honapok ?? params.honap, currentBudapestMonth());
  const supabase = await createClient();

  const rows: MonthlyHoursWithMonth[] = [];
  let summaryError = false;
  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_pricing_summary", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
    if (response.error) summaryError = true;
    for (const row of (response.data ?? []) as unknown as MonthlyHoursRow[]) rows.push({ ...row, month });
  }

  const users = Array.from(new Map(rows.map((row) => [row.user_id, row.user_name])).entries())
    .map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name, "hu"));
  const selectedUserId = params.user && users.some((user) => user.id === params.user) ? params.user : null;

  const details: MonthlyBookingDetailWithMonth[] = [];
  let detailsError = false;
  for (const month of months) {
    const [pricingResponse, titleResponse] = await Promise.all([
      supabase.rpc("admin_monthly_pricing_details", {
        p_month: monthStart(month)!, p_user_id: selectedUserId,
      }),
      supabase.rpc("admin_monthly_active_booking_details", {
        p_month: monthStart(month)!, p_user_id: selectedUserId,
      }),
    ]);
    if (pricingResponse.error || titleResponse.error) detailsError = true;
    const enriched = mergeBookingTitles(
      (pricingResponse.data ?? []) as unknown as Omit<MonthlyBookingDetail, "booking_title">[],
      (titleResponse.data ?? []) as unknown as MonthlyActiveBookingTitle[],
    );
    for (const row of enriched) details.push({ ...row, month });
  }

  const totalHours = rows.reduce((sum, row) => sum + Number(row.total_hours), 0);
  const totalDue = rows.reduce((sum, row) => sum + Number(row.calculated_due_huf), 0);
  const currentMonth = currentBudapestMonth();
  const monthQuery = months.join(",");
  const detailExportQuery = new URLSearchParams({ honapok: monthQuery });
  if (selectedUserId) detailExportQuery.set("user", selectedUserId);

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Havi órák és elszámolás</h1><p className="muted">Az élő előnézet az aktuális booking-adatokat számolja. A lezárt hónap auditált revisionje változtathatatlan pénzügyi snapshot.</p></div><Link className="button secondary" href="/admin/lemondasok">Lemondások</Link></header>
    {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}

    <form className="card stack" method="get">
      <MonthMultiSelect initialMonths={months} />
      <div className="monthly-filter"><button>Megjelenítés</button><a className="button secondary" href={`/admin/havi-orak/export?honapok=${encodeURIComponent(monthQuery)}`}>Összesítő CSV</a><a className="button secondary" href={`/admin/havi-orak/xlsx-export?honapok=${encodeURIComponent(monthQuery)}`}>Összesítő Excel</a></div>
    </form>

    {summaryError ? <p className="message error" role="alert">A havi óraszám betöltése nem sikerült teljes körűen. Az adatokat ne használd elszámolásra, amíg a hiba fennáll.</p> : null}
    <section className="card wide-card stack">
      <h2>Elszámolási összesítés</h2>
      <p className="muted">A Snapshot állapot a legutóbbi immutable revisiont mutatja. Korrekciókor új revision készül; a korábbi nem íródik át.</p>
      <div className="table-scroll"><table>
        <thead><tr><th>Hónap</th><th>Felhasználó</th><th>Összes óra</th><th>Fizetendő</th><th>Állapot</th><th>Revision készítése</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={`${row.month}-${row.user_id}`}><td>{row.month}</td><td>{row.user_name}</td><td>{hours(row.total_hours)}</td><td>{huf(row.calculated_due_huf)}</td><td>{row.pricing_state === "snapshot" ? `Snapshot #${row.revision_number}` : "Élő előnézet"}</td><td>{row.month < currentMonth ? <form action={createSettlementRevision} className="inline-form"><input type="hidden" name="month" value={row.month} /><input type="hidden" name="userId" value={row.user_id} /><input name="reason" maxLength={300} required placeholder="Új revision indoka" aria-label={`${row.user_name} revision indoka`} /><button type="submit">{row.pricing_state === "snapshot" ? "Új revision" : "Snapshot"}</button></form> : <span className="muted">A hónap még nyitott</span>}</td></tr>)}</tbody>
        <tfoot><tr><th colSpan={2}>Kijelölt hónapok mindösszesen</th><th>{hours(totalHours)}</th><th>{huf(totalDue)}</th><th colSpan={2}></th></tr></tfoot>
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
      <div className="monthly-detail-table-desktop table-scroll"><table>
        <thead><tr><th>Hónap</th><th>Felhasználó</th><th>Dátum</th><th>Helyiség</th><th>Foglalás címe</th><th>Idő</th><th>Óra</th><th>Árforrás</th><th>Óradíj</th><th>Összeg</th><th>Korrekció</th></tr></thead>
        <tbody>{details.map((row) => <tr key={`${row.month}-${row.booking_id}`}><td>{row.month}</td><td>{row.user_name}</td><td>{row.booking_date}</td><td>{row.room_name}</td><td>{row.booking_title || "—"}</td><td>{time(row.start_time)}–{time(row.end_time)}</td><td>{hours(row.total_hours)}</td><td>{rateSourceLabel[row.rate_source]}</td><td>{huf(row.hourly_rate_huf)}</td><td>{huf(row.amount_huf)}</td><td>{row.month < currentMonth ? <form action={correctHistoricalBookingRate} className="inline-form"><input type="hidden" name="month" value={row.month} /><input type="hidden" name="bookingId" value={row.booking_id} /><input name="hourlyRate" type="number" min="0" step="1" required defaultValue={row.hourly_rate_huf} aria-label="Korrigált óradíj" /><input name="reason" maxLength={300} required placeholder="Új korrekciós indok" aria-label="Korrekció indoka" /><button type="submit">Korrigálás + revision</button></form> : <span className="muted">—</span>}</td></tr>)}</tbody>
      </table></div>
      <div className="monthly-detail-list-mobile" aria-label="Tételes aktív foglalások mobil nézete">
        {details.map((row) => <article className="report-mobile-card" key={row.booking_id}>
          <div className="report-mobile-card-heading"><h3>{row.user_name}</h3><span>{row.month}</span></div>
          <dl className="report-mobile-details">
            <div><dt>Dátum</dt><dd>{row.booking_date}</dd></div>
            <div><dt>Helyiség</dt><dd>{row.room_name}</dd></div>
            <div><dt>Foglalás címe</dt><dd>{row.booking_title || "—"}</dd></div>
            <div><dt>Időtartam</dt><dd>{time(row.start_time)}–{time(row.end_time)}</dd></div>
            <div><dt>Összes óra</dt><dd>{hours(row.total_hours)}</dd></div>
            <div><dt>Óradíj</dt><dd>{huf(row.hourly_rate_huf)} · {rateSourceLabel[row.rate_source]}</dd></div>
            <div><dt>Összeg</dt><dd>{huf(row.amount_huf)}</dd></div>
            <div><dt>Állapot</dt><dd>{row.pricing_state === "snapshot" ? `Snapshot #${row.revision_number}` : "Élő előnézet"}</dd></div>
          </dl>
        </article>)}
      </div>
      {!details.length && !detailsError ? <p className="muted">A kiválasztott feltételekkel nincs aktív foglalás.</p> : null}
    </section>
  </section>;
}
