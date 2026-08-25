import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { recordPayment } from "./actions";

type PaymentStatus = "payable" | "partially_paid" | "paid" | "not_payable_adjustment";
type Row = {
  user_id: string;
  user_name: string;
  settlement_month: string;
  due_huf: number | string;
  paid_huf: number | string;
  remaining_huf: number | string;
  payment_status: PaymentStatus;
  is_closed: boolean;
  invoice_requested: boolean;
  invoice_number: string | null;
  last_payment_on: string | null;
};
type HistoryRow = {
  payment_id: string;
  user_id: string;
  user_name: string;
  settlement_month: string;
  amount_huf: number | string;
  paid_on: string;
  method: "cash" | "bank_transfer";
  destination: "private_otp" | "teem_otp" | "cash_register";
  admin_note: string | null;
  created_at: string;
  created_by_name: string;
};

function currentBudapestMonth() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
}
function todayBudapest() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
function huf(value: number | string) { return `${Number(value).toLocaleString("hu-HU")} Ft`; }
function statusLabel(value: PaymentStatus) {
  if (value === "partially_paid") return "Részben fizetve";
  if (value === "paid") return "Fizetve";
  if (value === "not_payable_adjustment") return "Nem fizetendő / korrekció";
  return "Fizetendő";
}
function methodLabel(value: HistoryRow["method"]) { return value === "cash" ? "Készpénz" : "Utalás"; }
function destinationLabel(value: HistoryRow["destination"]) {
  if (value === "private_otp") return "Privát OTP";
  if (value === "cash_register") return "Pénztár";
  return "Teem Kft. OTP";
}

export default async function PaymentsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const month = /^\d{4}-\d{2}$/.test(params.honap ?? "") ? params.honap! : currentBudapestMonth();
  const supabase = await createClient();
  const [summaryResponse, historyResponse] = await Promise.all([
    supabase.rpc("admin_monthly_payment_summary", { p_month: `${month}-01` }).returns<Row[]>(),
    supabase.rpc("admin_payment_history", { p_month: `${month}-01` }).returns<HistoryRow[]>(),
  ]);
  const rows = (summaryResponse.data ?? []) as unknown as Row[];
  const history = (historyResponse.data ?? []) as unknown as HistoryRow[];
  const totalDue = rows.reduce((sum, row) => sum + Number(row.due_huf), 0);
  const totalPaid = rows.reduce((sum, row) => sum + Number(row.paid_huf), 0);
  const totalRemaining = rows.reduce((sum, row) => sum + Number(row.remaining_huf), 0);
  const today = todayBudapest();

  return <section className="stack">
    <header className="page-heading">
      <div><p className="eyebrow">Adminisztráció</p><h1>Befizetések és kintlévőségek</h1><p className="muted">A fizetendő összeg a foglalási elszámolásból jön; a ténylegesen beérkezett befizetések ettől külön kerülnek nyilvántartásba.</p></div>
      <Link className="button secondary" href="/admin/havi-orak">Havi órák és fizetendő</Link>
    </header>

    {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
    {summaryResponse.error || historyResponse.error ? <p className="message error" role="alert">A befizetési adatok nem tölthetők be teljes körűen. Az adatokat ne használd elszámolásra, amíg a hiba fennáll.</p> : null}

    <form className="card monthly-filter" method="get">
      <label>Hónap<input type="month" name="honap" defaultValue={month} /></label>
      <button>Megjelenítés</button>
    </form>

    <section className="card wide-card stack">
      <div><p className="eyebrow">Havi pénzügyi állapot</p><h2>Fizetendő, befizetve, kintlévőség</h2></div>
      <div className="table-scroll"><table>
        <thead><tr><th>Felhasználó</th><th>Fizetendő</th><th>Befizetve</th><th>Tartozás</th><th>Státusz</th><th>Utolsó befizetés</th><th>Elszámolás</th><th>Művelet</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={row.user_id}>
          <td>{row.user_name}</td><td>{huf(row.due_huf)}</td><td>{huf(row.paid_huf)}</td><td><strong>{huf(row.remaining_huf)}</strong></td><td>{statusLabel(row.payment_status)}</td><td>{row.last_payment_on ?? "—"}</td><td>{row.is_closed ? "Lezárt" : "Nyitott"}</td>
          <td>{Number(row.remaining_huf) > 0 ? <details>
            <summary className="button secondary">Befizetés</summary>
            <form action={recordPayment} className="stack" style={{ minWidth: "18rem", paddingTop: ".75rem" }}>
              <input type="hidden" name="userId" value={row.user_id} /><input type="hidden" name="month" value={month} />
              <label>Összeg (Ft)<input name="amountHuf" type="number" min="1" step="1" max={Number(row.remaining_huf)} defaultValue={Number(row.remaining_huf)} required /></label>
              <label>Befizetés dátuma<input name="paidOn" type="date" defaultValue={today} required /></label>
              <label>Fizetési mód<select name="method" defaultValue="bank_transfer"><option value="bank_transfer">Utalás</option><option value="cash">Készpénz</option></select></label>
              <label>Pénz célhelye<select name="destination" defaultValue="teem_otp"><option value="teem_otp">Teem Kft. OTP</option><option value="private_otp">Privát OTP</option><option value="cash_register">Pénztár</option></select></label>
              <label>Admin megjegyzés<textarea name="adminNote" rows={2} maxLength={500} /></label>
              <button type="submit">Befizetés rögzítése</button>
            </form>
          </details> : "—"}</td>
        </tr>)}</tbody>
        <tfoot><tr><th>Összesen</th><th>{huf(totalDue)}</th><th>{huf(totalPaid)}</th><th>{huf(totalRemaining)}</th><th colSpan={4} /></tr></tfoot>
      </table></div>
      {rows.length || summaryResponse.error ? null : <p className="muted">Ebben a hónapban nincs fizetendő vagy rögzített befizetés.</p>}
    </section>

    <section className="card wide-card stack">
      <div><p className="eyebrow">Auditálható részletek</p><h2>Befizetési előzmények</h2></div>
      <div className="table-scroll"><table>
        <thead><tr><th>Dátum</th><th>Felhasználó</th><th>Összeg</th><th>Mód</th><th>Célhely</th><th>Megjegyzés</th><th>Rögzítette</th></tr></thead>
        <tbody>{history.map((payment) => <tr key={payment.payment_id}><td>{payment.paid_on}</td><td>{payment.user_name}</td><td>{huf(payment.amount_huf)}</td><td>{methodLabel(payment.method)}</td><td>{destinationLabel(payment.destination)}</td><td>{payment.admin_note ?? "—"}</td><td>{payment.created_by_name}</td></tr>)}</tbody>
      </table></div>
      {history.length || historyResponse.error ? null : <p className="muted">Ehhez a hónaphoz még nincs rögzített befizetés.</p>}
    </section>
  </section>;
}
