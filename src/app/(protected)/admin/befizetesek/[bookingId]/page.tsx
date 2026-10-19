import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { paymentBalance, paymentLabel } from "@/lib/booking-payments";
import { recordBookingPayment, voidBookingPayment } from "./actions";

type Context = { booking_id: string; user_name: string; room_name: string; start_at: string; end_at: string; booking_status: string; booking_title: string | null; amount_huf: number; paid_huf: number; is_closed: boolean };
type Receipt = { payment_id: string; amount_huf: number; paid_on: string; method: string; destination: string; admin_note: string | null; void_reason: string | null };
const huf = (n: number | string) => `${Number(n).toLocaleString("hu-HU")} Ft`;
const destinationNames: Record<string,string> = { cash_register: "Készpénz", private_otp: "Privát OTP", teem_otp: "TEEM OTP" };

export default async function BookingPaymentsPage({ params, searchParams }: { params: Promise<{ bookingId: string }>; searchParams: Promise<Record<string,string | undefined>> }) {
  await requireAdmin();
  const { bookingId } = await params;
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(bookingId)) notFound();
  const messages = await searchParams;
  const supabase = await createClient();
  const [contextResult, historyResult] = await Promise.all([
    supabase.rpc("admin_booking_payment_context", { p_booking_id: bookingId }),
    supabase.rpc("admin_booking_payment_history", { p_booking_id: bookingId }),
  ]);
  if (contextResult.error || historyResult.error) return <section className="stack"><h1>Foglalás befizetései</h1><p role="alert" className="message error">A befizetési adatok nem tölthetők be. Hiányos adatokkal nem végezhető művelet.</p></section>;
  const booking = (contextResult.data as Context[] | null)?.[0];
  if (!booking) notFound();
  const receipts = (historyResult.data ?? []) as Receipt[];
  const date = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(booking.start_at));
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  const balance = paymentBalance(Number(booking.amount_huf), Number(booking.paid_huf));
  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Foglalás befizetései</h1><p>{booking.user_name} · {booking.room_name} · {date}{booking.booking_title ? ` · ${booking.booking_title}` : ""}</p></div><Link className="button secondary" href={`/foglalasok?datum=${date}`}>Vissza a naptárhoz</Link></header>
    <Link href={`/admin/havi-orak?honapok=${date.slice(0,7)}`}>Havi elszámolás</Link>
    {messages.hiba || messages.uzenet ? <p role="status" className={`message ${messages.hiba ? "error" : "success"}`}>{messages.hiba ?? messages.uzenet}</p> : null}
    <article className="card stack"><h2>{paymentLabel(balance)}{booking.is_closed ? "" : " · előzetes"}</h2><dl className="report-mobile-details"><div><dt>Foglalás díja</dt><dd>{huf(booking.amount_huf)}</dd></div><div><dt>Befizetve</dt><dd>{huf(booking.paid_huf)}</dd></div><div><dt>Még fizetendő</dt><dd>{huf(balance.remaining_huf)}</dd></div><div><dt>Túlfizetés</dt><dd>{huf(balance.overpaid_huf)}</dd></div></dl><p className="muted">Részleges lemondás után az összetartozó foglalásrészek díját és befizetését együtt mutatjuk. A nyitott hónap díja a havi óraszámmal még változhat. A befizetés nem módosítja az óraszámot vagy a díjszabást. A havi összesítő az egyéb havi befizetéseket is figyelembe veszi.</p></article>
    {booking.booking_status === "active" ? <form action={recordBookingPayment} className="card stack">
      <h2>Befizetés rögzítése</h2><input type="hidden" name="bookingId" value={bookingId}/><input type="hidden" name="idempotencyKey" value={crypto.randomUUID()}/>
      <label>Átvett összeg (Ft)<input name="amount" type="number" min="1" max="100000000" step="1" required /></label>
      <label>Befizetés dátuma<input name="paidOn" type="date" defaultValue={today} max={today} required /></label>
      <label>Fizetési mód<select name="method" defaultValue="cash"><option value="cash">Készpénz</option><option value="bank_transfer">Átutalás</option></select></label>
      <label>Pénz célhelye<select name="destination" defaultValue="cash_register"><option value="cash_register">Készpénz</option><option value="private_otp">Privát OTP</option><option value="teem_otp">TEEM OTP</option></select></label>
      <label>Megjegyzés<input name="note" maxLength={300} placeholder="Például: borítékban átvéve" /></label><button type="submit">Befizetés rögzítése</button>
    </form> : <p className="message">Lemondott foglalás. A korábbi befizetés megmarad a havi egyenlegben; új befizetés nem rögzíthető.</p>}
    <section className="stack"><h2>Befizetési történet</h2>{receipts.length ? receipts.map((receipt) => <article className="card stack" key={receipt.payment_id}><strong>{huf(receipt.amount_huf)} · {receipt.paid_on}</strong><p>{receipt.method === "cash" ? "Készpénz" : "Átutalás"} · {destinationNames[receipt.destination]}{receipt.admin_note ? ` · ${receipt.admin_note}` : ""}</p>{receipt.void_reason ? <p>Érvénytelenített rögzítés: {receipt.void_reason}</p> : <details><summary>Téves rögzítés javítása</summary><form action={voidBookingPayment} className="stack"><input type="hidden" name="bookingId" value={bookingId}/><input type="hidden" name="paymentId" value={receipt.payment_id}/><label>Javítás indoka<input name="reason" required maxLength={300}/></label><label><input type="checkbox" name="confirm" value="yes" required/> Megerősítem: ez téves rögzítés, nem tényleges pénzvisszafizetés.</label><button type="submit">Rögzítés érvénytelenítése</button></form></details>}</article>) : <p className="muted">Még nincs rögzített befizetés.</p>}</section>
  </section>;
}
