import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { monthStart, selectedMonths, type MonthlyBookingDetail, type MonthlyBookingDetailWithMonth, type MonthlyHoursRow, type MonthlyHoursWithMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";
import { closeMonthlySettlement } from "./actions";
import { MonthMultiSelect } from "./month-multi-select";

type PricingScheme = "tiered" | "progressive" | "free";
type MonthlyPricingRow = {
  user_id: string;
  user_name: string;
  settlement_month: string;
  pricing_scheme: PricingScheme;
  normal_minutes: number;
  special_minutes: number;
  total_minutes: number;
  normal_due_huf: number | string;
  special_due_huf: number | string;
  calculated_due_huf: number | string;
  pricing_breakdown: unknown;
  calculation_input_hash: string;
};
type MonthlyPricingWithMonth = MonthlyPricingRow & { month: string };

type SettlementStatusRow = {
  user_id: string;
  user_name: string;
  settlement_month: string;
  is_closed: boolean;
  closed_at: string | null;
  revision_id: string | null;
  revision_number: number | null;
  pricing_scheme: PricingScheme | null;
  normal_minutes: number | null;
  special_minutes: number | null;
  normal_due_huf: number | string | null;
  special_due_huf: number | string | null;
  calculated_due_huf: number | string | null;
  calculation_input_hash: string | null;
};
type SettlementStatusWithMonth = SettlementStatusRow & { month: string };

type DisplayPricingRow = MonthlyPricingWithMonth & {
  is_closed: boolean;
  closed_at: string | null;
  revision_number: number | null;
};

function currentBudapestMonth() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
}
function hours(value: number | string) {
  return Number(value).toLocaleString("hu-HU", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function minutesToHours(value: number) { return hours(value / 60); }
function huf(value: number | string) { return `${Number(value).toLocaleString("hu-HU")} Ft`; }
function time(value: string) { return value.slice(0, 5); }
function schemeLabel(value: PricingScheme) {
  if (value === "progressive") return "Progresszív";
  if (value === "free") return "Free – 0 Ft";
  return "Sávos";
}
function closedAt(value: string | null) {
  if (!value) return "";
  return new Intl.DateTimeFormat("hu-HU", { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Budapest" }).format(new Date(value));
}

export default async function MonthlyHoursPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const currentMonth = currentBudapestMonth();
  const months = selectedMonths(params.honapok ?? params.honap, currentMonth);
  const supabase = await createClient();

  const rows: MonthlyHoursWithMonth[] = [];
  let summaryError = false;
  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_booking_hours", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
    if (response.error) summaryError = true;
    for (const row of (response.data ?? []) as unknown as MonthlyHoursRow[]) rows.push({ ...row, month });
  }

  const pricingRows: MonthlyPricingWithMonth[] = [];
  let pricingError = false;
  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_pricing_summary", { p_month: monthStart(month)! }).returns<MonthlyPricingRow[]>();
    if (response.error) pricingError = true;
    for (const row of (response.data ?? []) as unknown as MonthlyPricingRow[]) pricingRows.push({ ...row, month });
  }

  const settlementStatuses: SettlementStatusWithMonth[] = [];
  let settlementError = false;
  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_settlement_status", { p_month: monthStart(month)! }).returns<SettlementStatusRow[]>();
    if (response.error) settlementError = true;
    for (const row of (response.data ?? []) as unknown as SettlementStatusRow[]) settlementStatuses.push({ ...row, month });
  }

  const statusByKey = new Map(settlementStatuses.map((row) => [`${row.month}:${row.user_id}`, row]));
  const liveByKey = new Map(pricingRows.map((row) => [`${row.month}:${row.user_id}`, row]));
  const displayByKey = new Map<string, DisplayPricingRow>();

  for (const row of pricingRows) {
    const status = statusByKey.get(`${row.month}:${row.user_id}`);
    if (status?.is_closed && status.pricing_scheme && status.normal_minutes !== null && status.special_minutes !== null && status.calculated_due_huf !== null) {
      displayByKey.set(`${row.month}:${row.user_id}`, {
        ...row,
        user_name: status.user_name,
        pricing_scheme: status.pricing_scheme,
        normal_minutes: status.normal_minutes,
        special_minutes: status.special_minutes,
        total_minutes: status.normal_minutes + status.special_minutes,
        normal_due_huf: status.normal_due_huf ?? 0,
        special_due_huf: status.special_due_huf ?? 0,
        calculated_due_huf: status.calculated_due_huf,
        calculation_input_hash: status.calculation_input_hash ?? row.calculation_input_hash,
        is_closed: true,
        closed_at: status.closed_at,
        revision_number: status.revision_number,
      });
    } else {
      displayByKey.set(`${row.month}:${row.user_id}`, {
        ...row,
        is_closed: false,
        closed_at: null,
        revision_number: null,
      });
    }
  }

  for (const status of settlementStatuses) {
    const key = `${status.month}:${status.user_id}`;
    if (!status.is_closed || displayByKey.has(key) || !status.pricing_scheme || status.normal_minutes === null || status.special_minutes === null || status.calculated_due_huf === null) continue;
    displayByKey.set(key, {
      user_id: status.user_id,
      user_name: status.user_name,
      settlement_month: status.settlement_month,
      pricing_scheme: status.pricing_scheme,
      normal_minutes: status.normal_minutes,
      special_minutes: status.special_minutes,
      total_minutes: status.normal_minutes + status.special_minutes,
      normal_due_huf: status.normal_due_huf ?? 0,
      special_due_huf: status.special_due_huf ?? 0,
      calculated_due_huf: status.calculated_due_huf,
      pricing_breakdown: null,
      calculation_input_hash: status.calculation_input_hash ?? "",
      month: status.month,
      is_closed: true,
      closed_at: status.closed_at,
      revision_number: status.revision_number,
    });
  }

  const displayPricingRows = Array.from(displayByKey.values()).sort((a, b) => a.month.localeCompare(b.month) || a.user_name.localeCompare(b.user_name, "hu"));

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
  const totalDue = displayPricingRows.reduce((sum, row) => sum + Number(row.calculated_due_huf), 0);
  const monthQuery = months.join(",");
  const detailExportQuery = new URLSearchParams({ honapok: monthQuery });
  if (selectedUserId) detailExportQuery.set("user", selectedUserId);

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Havi órák és fizetendő</h1><p className="muted">Számlázási és elszámolási alap. Kizárólag az aktív, le nem mondott foglalások szerepelnek benne; lezárás után a történeti snapshot változatlan marad.</p></div><Link className="button secondary" href="/admin/lemondasok">Lemondások</Link></header>

    {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}

    <form className="card stack" method="get">
      <MonthMultiSelect initialMonths={months} />
      <div className="monthly-filter"><button>Megjelenítés</button><a className="button secondary" href={`/admin/havi-orak/export?honapok=${encodeURIComponent(monthQuery)}`}>Összesítő CSV</a></div>
    </form>

    {summaryError ? <p className="message error" role="alert">A havi óraszám betöltése nem sikerült teljes körűen. Az adatokat ne használd elszámolásra, amíg a hiba fennáll.</p> : null}
    {pricingError ? <p className="message error" role="alert">A havi díjszámítás betöltése nem sikerült teljes körűen. A fizetendő összegeket ne használd elszámolásra, amíg a hiba fennáll.</p> : null}
    {settlementError ? <p className="message error" role="alert">A lezárási állapot betöltése nem sikerült. Havi elszámolást addig ne zárj le.</p> : null}

    <section className="card wide-card stack">
      <div><p className="eyebrow">Pénzügyi összesítés</p><h2>Havi fizetendő</h2><p className="muted">Nyitott hónapnál élő kalkuláció látható. A már lezárt hónapnál a revision snapshot jelenik meg, ezért későbbi ár- vagy díjazási mód változás nem írja át a múltat.</p></div>
      <div className="table-scroll"><table>
        <thead><tr><th>Hónap</th><th>Felhasználó</th><th>Normál óra</th><th>Tréningterem csoportos</th><th>Díjazás</th><th>Normál díj</th><th>Tréningterem díj</th><th>Fizetendő</th><th>Állapot</th><th>Művelet</th></tr></thead>
        <tbody>{displayPricingRows.map((row) => {
          const canClose = !settlementError && !row.is_closed && row.month < currentMonth;
          return <tr key={`${row.month}-${row.user_id}`}>
            <td>{row.month}</td><td>{row.user_name}</td><td>{minutesToHours(row.normal_minutes)}</td><td>{minutesToHours(row.special_minutes)}</td><td>{schemeLabel(row.pricing_scheme)}</td><td>{huf(row.normal_due_huf)}</td><td>{huf(row.special_due_huf)}</td><td><strong>{huf(row.calculated_due_huf)}</strong></td>
            <td>{row.is_closed ? <><strong>Lezárva</strong><br /><span className="muted">rev. {row.revision_number ?? "—"}{row.closed_at ? ` · ${closedAt(row.closed_at)}` : ""}</span></> : row.month < currentMonth ? "Lezárható" : "Folyamatban"}</td>
            <td>{canClose ? <form action={closeMonthlySettlement}><input type="hidden" name="userId" value={row.user_id} /><input type="hidden" name="month" value={row.month} /><input type="hidden" name="returnMonths" value={monthQuery} /><button type="submit">Hónap lezárása</button></form> : "—"}</td>
          </tr>;
        })}</tbody>
        <tfoot><tr><th colSpan={7}>Kijelölt hónapok fizetendője</th><th>{huf(totalDue)}</th><th colSpan={2} /></tr></tfoot>
      </table></div>
      {displayPricingRows.length || pricingError || settlementError ? null : <p className="muted">A kijelölt hónapokban nincs elszámolható aktív foglalás.</p>}
    </section>

    <section className="card wide-card stack">
      <h2>Óra-összesítés</h2>
      <p className="muted">A hónap külön oszlop, ezért több kijelölt hónap adatai sem keverednek össze. Lemondott foglalás nem szerepelhet.</p>
      <div className="table-scroll"><table>
        <thead><tr><th>Hónap</th><th>Felhasználó</th><th>Összes óra</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={`${row.month}-${row.user_id}`}><td>{row.month}</td><td>{row.user_name}</td><td>{hours(row.total_hours)}</td></tr>)}</tbody>
        <tfoot><tr><th colSpan={2}>Kijelölt hónapok mindösszesen</th><th>{hours(totalHours)}</th></tr></tfoot>
      </table></div>
      {rows.length ? null : <p className="muted">A kijelölt hónapokban nincs elszámolható aktív foglalás.</p>}
    </section>

    <section className="card wide-card stack">
      <div><p className="eyebrow">Ellenőrzés</p><h2>Tételes aktív foglalások</h2><p className="muted">Minden jelenleg aktív foglalás visszaellenőrizhető. Lezárt hónap pénzügyi alapja azonban már a fenti immutable snapshot.</p></div>
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
