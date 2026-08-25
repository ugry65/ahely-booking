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

export default async function PaymentsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const month = /^\d{4}-\d{2}$/.test(params.honap ?? "") ? params.honap! : currentBudapestMonth();
  const supabase = await createClient();
  const response = await supabase.rpc("admin_monthly_payment_summary", { p_month: `${month}-01` }).returns<Row[]>();
  const rows = (response.data ?? []) as unknown as Row[];
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
    {response.error ? <p className="message error" role="alert">A befizetési összesítő nem tölthető be. Az adatokat ne használd elszámolásra, amíg a hiba fennáll.</p> : null}

    <form className="card monthly-filter" method="get">
      <label>Hónap<input type="month" name="honap" defaultValue={month} /></label>
      <button>Megjelenítés</button>
    </form>

    <section className="card wide-card stack">
      <div className="table-scroll"><table>
        <thead><tr><th>Felhasználó</th><th>Fizetendő</th><th>Befizetve</th><th>Tartozás</th><th>Státusz</th><th>Utolsó befizetés</th><th>Elszámolás</th><th>Művelet</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={row.user_id}>
          <td>{row.user_name}</td>
          <td>{huf(row.due_huf)}</td>
          <td>{huf(row.paid_huf)}</td>
          <td><strong>{huf(row.remaining_huf)}</strong></td>
          <td>{statusLabel(row.payment_status)}</td>
          <td>{row.last_payment_on ?? "—"}</td>
          <td>{row.is_closed ? "Lezárt" : "Nyitott"}</td>
          <td>{Number(row.remaining_huf) > 0 ? <details>
            <summary className="button secondary">Befizetés</summary>
            <form action={recordPayment} className="stack" style={{ minWidth: "18rem", paddingTop: ".75rem" }}>
              <input type="hidden" name="userId" value={row.user_id} />
              <input type="hidden" name="month" value={month} />
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
      {rows.length || response.error ? null : <p className="muted">Ebben a hónapban nincs fizetendő vagy rögzített befizetés.</p>}
    </section>
  </section>;
}
