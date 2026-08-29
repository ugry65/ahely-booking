import Link from "next/link";
import { requireActiveProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createRecurringBooking } from "./actions";
import { RecurringExceptionCalendar } from "./recurring-exception-calendar";
import { RecurringEndFields } from "../recurring-end-fields";

type RepeatableRoom = { room_id: string; room_name: string; is_training_room: boolean; display_order: number };
type Occurrence = { occurrence_index: number; service_date: string; start_at: string; end_at: string; booking_id?: string; status?: string; reason?: string };
type SeriesResult = { series_id: string; created: Occurrence[]; skipped: Occurrence[] };
const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

function budapestToday() { return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()); }
function timeOptions() { return Array.from({ length: 31 }, (_, index) => { const minute = 420 + index * 30; return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`; }); }
function occurrenceLabel(item: Occurrence) { return new Intl.DateTimeFormat("hu-HU", { timeZone: "Europe/Budapest", year: "numeric", month: "long", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(item.start_at)); }

export default async function RecurringBookingPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireActiveProfile();
  const params = await searchParams; const supabase = await createClient();
  const roomsResult = await supabase.rpc("list_repeatable_rooms").returns<RepeatableRoom[]>();
  const rooms = (roomsResult.data ?? []) as unknown as RepeatableRoom[];
  let result: SeriesResult | null = null; let resultError = false;
  if (params.sorozat && UUID_PATTERN.test(params.sorozat)) {
    const response = await supabase.rpc("get_my_booking_series_result", { p_series_id: params.sorozat });
    if (response.error) resultError = true; else result = response.data as unknown as SeriesResult;
  }
  const today = budapestToday(); const times = timeOptions();

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Sorozatfoglalás</p><h1>Ismétlődő foglalás</h1><p className="muted">Napi, heti, kétheti vagy havi alkalmak egyetlen biztonságos művelettel.</p></div><Link className="button secondary" href="/foglalasok">Vissza a naptárhoz</Link></header>
    {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
    {roomsResult.error ? <p className="message error" role="alert">A jogosult helyiségek betöltése nem sikerült.</p> : null}
    {resultError ? <p className="message error" role="alert">A sorozat eredményének betöltése nem sikerült.</p> : null}
    {result ? <section className="card wide-card stack result-card" aria-labelledby="series-result-title"><div><p className="eyebrow">Sikeres művelet</p><h2 id="series-result-title">A sorozat elkészült</h2><p><strong>{result.created.length}</strong> alkalom létrejött, <strong>{result.skipped.length}</strong> alkalom kimaradt.</p></div>
      <div className="result-columns"><details open><summary>Létrejött alkalmak ({result.created.length})</summary><ul className="result-list">{result.created.map((item) => <li key={item.occurrence_index}>{occurrenceLabel(item)}</li>)}</ul></details><details open><summary>Kimaradt alkalmak ({result.skipped.length})</summary>{result.skipped.length ? <ul className="result-list">{result.skipped.map((item) => <li key={item.occurrence_index}>{occurrenceLabel(item)} – {item.reason}</li>)}</ul> : <p className="muted">Nincs kimaradt alkalom.</p>}</details></div>
      <Link className="button" href="/foglalasaim">Foglalásaim megtekintése</Link>
    </section> : null}

    <div className="card wide-card recurring-form-card stack"><div><h2>Új sorozat</h2><p className="muted">Csak olyan helyiség jelenik meg, amelyre ismétlődő foglalási jogod van.</p></div>
      {rooms.length ? <form action={createRecurringBooking} className="stack">
        <input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
        <label>Helyiség<select name="roomId" required defaultValue=""><option value="" disabled>Válassz helyiséget</option>{rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}{room.is_training_room ? " – Tréningterem" : ""}</option>)}</select></label>
        <div className="form-row"><label>Első alkalom dátuma<input name="date" type="date" required defaultValue={today} /></label><label>Gyakoriság<select name="frequency" defaultValue="weekly"><option value="daily">Naponta</option><option value="weekly">Hetente</option><option value="biweekly">Kéthetente</option><option value="monthly">Havonta</option></select></label></div>
        <div className="form-row"><label>Kezdés<select name="startTime" required defaultValue="09:00">{times.slice(0, -2).map((time) => <option key={time}>{time}</option>)}</select></label><label>Befejezés<select name="endTime" required defaultValue="10:00">{times.slice(2).map((time) => <option key={time}>{time}</option>)}</select></label></div>
        <RecurringEndFields initialDate={today} />
        <RecurringExceptionCalendar />
        <label>Ütközés kezelése<select name="conflictPolicy" defaultValue="abort_all"><option value="abort_all">Teljes sorozat megszakítása</option><option value="create_available">Csak a szabad alkalmak létrehozása</option></select><span className="muted form-help">Megszakításnál egyetlen alkalom sem jön létre. A másik lehetőség a foglalt vagy szabálytalan alkalmakat kihagyja és pontosan felsorolja.</span></label>
        <label>Használat<select name="useType" defaultValue="individual"><option value="individual">Egyéni</option><option value="group">Csoportos</option></select></label>
        <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} placeholder="Opcionális" /></label>
        <button type="submit">Sorozat létrehozása</button>
      </form> : <p className="muted">Nincs ismétlődő foglalásra jogosult helyiséged. Kérj jogosultságot az adminisztrátortól.</p>}
    </div>
  </section>;
}
