import { createClient } from "@/lib/supabase/server";
import { paymentLabel, type MonthlyPaymentBalance } from "@/lib/booking-payments";

const huf = (value: number | string) => `${Number(value).toLocaleString("hu-HU")} Ft`;
export async function PaymentOverview({ months }: { months: string[] }) {
  const supabase = await createClient();
  const responses = await Promise.all(months.map(async (month) => ({ month, ...await supabase.rpc("admin_monthly_booking_payment_summary", { p_month: `${month}-01` }) })));
  if (responses.some((response) => response.error)) return <p className="message error" role="alert">A befizetési összesítés nem tölthető be teljes körűen. A hiányzó adat nem jelent 0 Ft befizetést.</p>;
  const rows = responses.flatMap((response) => ((response.data ?? []) as MonthlyPaymentBalance[]).map((row) => ({ ...row, month: response.month })));
  return <section className="card wide-card stack"><h2>Befizetések és fennmaradó összeg</h2><p className="muted">A foglalási és az egyéb havi befizetések egyszer szerepelnek. Nyitott hónapban az egyenleg előzetes. A lemondott foglalásra átvett pénz is megmarad a havi egyenlegben.</p>
    <div className="monthly-summary-table-desktop table-scroll"><table><thead><tr><th>Hónap</th><th>Felhasználó</th><th>Havi díj</th><th>Befizetve</th><th>Még fizetendő</th><th>Túlfizetés</th><th>Fizetési állapot</th></tr></thead><tbody>{rows.map((row) => <tr key={`${row.month}-${row.user_id}`}><td>{row.month}</td><td>{row.user_name}</td><td>{huf(row.due_huf)}</td><td>{huf(row.paid_huf)}</td><td>{huf(row.remaining_huf)}</td><td>{huf(row.overpaid_huf)}</td><td>{paymentLabel(row)}</td></tr>)}</tbody></table></div>
    <div className="monthly-summary-list-mobile">{rows.map((row) => <article className="report-mobile-card" key={`${row.month}-${row.user_id}`}><div className="report-mobile-card-heading"><h3>{row.user_name}</h3><span>{row.month}</span></div><dl className="report-mobile-details"><div><dt>Havi díj</dt><dd>{huf(row.due_huf)}</dd></div><div><dt>Befizetve</dt><dd>{huf(row.paid_huf)}</dd></div><div><dt>Még fizetendő</dt><dd>{huf(row.remaining_huf)}</dd></div><div><dt>Túlfizetés</dt><dd>{huf(row.overpaid_huf)}</dd></div><div><dt>Fizetési állapot</dt><dd>{paymentLabel(row)}</dd></div></dl></article>)}</div>
    {!rows.length ? <p>Nincs elszámolás vagy befizetés a kijelölt hónapokban.</p> : null}
  </section>;
}
