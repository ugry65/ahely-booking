import Link from "next/link";
import { loadRoomCalendar } from "@/lib/room-calendar-data";
import { advanceLimit, bookingMinutes, freeRoomSlots, parseRoomCalendarFilter, roomCalendarUrl, slotBookingLink, type FreeSlot, type RoomCalendarBooking } from "@/lib/room-calendar";
import { budapestToday, budapestDateFromIso, civilDateLabel, groupBookingsByBudapestDate, monthGrid, shiftMonth } from "@/lib/my-bookings-calendar";
import { timeLabel } from "@/lib/room-occupancy";
import styles from "./room-calendar.module.css";

const weekdays = ["vasárnap", "hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat"];
function dateLabel(date: string) { return civilDateLabel(date, { month: "long", day: "numeric", weekday: "long" }); }
function owner(b: RoomCalendarBooking) { return b.is_own ? "Saját foglalás" : b.booker_display_name || "Foglalt"; }
function interval(b: RoomCalendarBooking) { const m=bookingMinutes(b); return `${timeLabel(m.start)}–${timeLabel(m.end)}`; }

export async function RoomCalendarView({ params }: { params: Record<string, string | undefined> }) {
  const today = budapestToday(), now = new Date();
  let filter: ReturnType<typeof parseRoomCalendarFilter>;
  let data: Awaited<ReturnType<typeof loadRoomCalendar>>;
  try { filter = parseRoomCalendarFilter(params, today); data = await loadRoomCalendar(filter); }
  catch (e) { return <section className="stack"><h1>Szobafoglaltság</h1><div className="message error" role="alert">{e instanceof Error ? e.message : "A foglaltság betöltése nem sikerült."}</div><Link href="/foglalasok?view=month">Vissza a havi nézethez</Link><Link href="/foglalasok">Napi naptár</Link></section>; }
  const room = data.room;
  if (!room) return <section className="card empty-state"><h1>Nincs foglalható helyiséged</h1><p>Kérj jogosultságot az A-Hely adminisztrátorától.</p><Link href="/foglalasok">Napi naptár</Link></section>;
  filter = { ...filter, roomId: room.room_id };
  const gaps = freeRoomSlots(data.bookings, filter, data.opening);
  const limit = advanceLimit(data.profile.role, room, data.defaultDays, data.trainingDays, data.override);
  const grouped = groupBookingsByBudapestDate(data.bookings);
  const gapsByDate = new Map<string, FreeSlot[]>();
  for (const gap of gaps) { const list = gapsByDate.get(gap.date) ?? []; list.push(gap); gapsByDate.set(gap.date, list); }
  const selectedBookings = grouped[filter.date] ?? [];
  const selectedGaps = gapsByDate.get(filter.date) ?? [];
  function slotAction(slot: FreeSlot) {
    const action = slotBookingLink(room!.room_id, slot, filter.duration, today, limit, now);
    return action.href ? <Link className="button secondary" href={action.href}>Foglalás</Link> : <span className={styles.limit}>{action.reason}</span>;
  }
  function slotRow(slot: FreeSlot) {
    return <article className={styles.row} key={`${slot.date}-${slot.start}`}><div><strong>{dateLabel(slot.date)}</strong><p className={styles.free}>{timeLabel(slot.start)}–{timeLabel(slot.end)} szabad</p><span className="muted">{((slot.end-slot.start)/60).toLocaleString("hu-HU")} egybefüggő óra</span></div>{slotAction(slot)}</article>;
  }
  const listBookings = data.bookings.filter(b => !filter.weekday || String(new Date(`${budapestDateFromIso(b.start_at)}T12:00:00Z`).getUTCDay()) === filter.weekday);
  const resultCount = filter.kind === "free" ? gaps.length : listBookings.length;
  const requestedPage = Number(params.page ?? "1");
  const pages = Math.max(1, Math.ceil(resultCount / 100));
  const page = Number.isSafeInteger(requestedPage) && requestedPage > 0 ? Math.min(requestedPage, pages) : 1;
  const fromRow = (page-1)*100;
  return <section className={`stack ${styles.page}`}>
    <header className={styles.heading}><div><p className="eyebrow">Foglalási naptár</p><h1>{room.room_name}</h1><p className="muted">Foglaltság és egybefüggő szabad időszakok</p></div>
      <nav aria-label="Naptárnézet" className={styles.tabs}><Link className="button secondary" href={`/foglalasok?datum=${filter.date}&room=${room.room_id}`}>Napi</Link><Link className="button secondary" aria-current={filter.view === "month" ? "page" : undefined} href={roomCalendarUrl(filter,{view:"month",date:filter.view === "list" ? filter.from : filter.date})}>Havi</Link><Link className="button secondary" aria-current={filter.view === "list" ? "page" : undefined} href={roomCalendarUrl(filter,{view:"list"})}>Lista</Link></nav>
    </header>
    <form key={roomCalendarUrl(filter)} method="get" className={`card ${styles.filters}`}>
      <input type="hidden" name="view" value={filter.view}/><input type="hidden" name="datum" value={filter.date}/>
      <label>Szoba<select name="room" defaultValue={room.room_id}>{data.rooms.map(r=><option value={r.room_id} key={r.room_id}>{r.room_name}</option>)}</select></label>
      {filter.view === "month" ? <label>Hónap<input type="month" name="month" defaultValue={filter.date.slice(0,7)} required/></label> : null}
      {filter.view === "list" ? <><label>Dátumtól<input type="date" name="from" defaultValue={filter.from} required/></label><label>Dátumig<input type="date" name="to" defaultValue={filter.to} required/></label><label>Lista tartalma<select name="kind" defaultValue={filter.kind}><option value="bookings">Foglalások</option><option value="free">Szabad időpontok</option></select></label></> : <input type="hidden" name="kind" value={filter.kind}/>}
      <label>Hét napja<select name="weekday" defaultValue={filter.weekday}><option value="">Minden nap</option>{[1,2,3,4,5,6,0].map(n=><option key={n} value={n}>{weekdays[n]}</option>)}</select></label>
      <label>Szabad idő keresése ettől<input name="start" type="time" step="1800" min="07:00" max="22:00" defaultValue={timeLabel(filter.start)} required/></label>
      <label>Eddig<input name="end" type="time" step="1800" min="07:00" max="22:00" defaultValue={timeLabel(filter.end)} required/></label>
      <label>Legalább ennyi idő<select name="duration" defaultValue={filter.duration}>{Array.from({length:29},(_,i)=>60+i*30).map(m=><option key={m} value={m}>{(m/60).toLocaleString("hu-HU")} óra</option>)}</select></label>
      <button type="submit">Mutasd</button>
      <p className={`muted ${styles.full}`}>Az idősáv és az időtartam a szabad időpontokat szűri. A foglaltsági sáv minden foglalást mutat.</p>
    </form>
    {limit !== null ? <p className="muted">Ebben a szobában legfeljebb {limit} napra előre foglalhatsz. Távolabbi időpontok foglaltságát is megtekintheted.</p> : null}
    {filter.view === "month" ? <>
      <section className={`card ${styles.month}`}>
        <div className={styles.heading}><h2>{civilDateLabel(filter.date,{year:"numeric",month:"long"})}</h2><nav className={styles.tabs} aria-label="Hónap választása"><Link className="button secondary" href={roomCalendarUrl(filter,{date:shiftMonth(filter.date,-1)})}>← Előző</Link><Link className="button secondary" href={roomCalendarUrl(filter,{date:today})}>Ma</Link><Link className="button secondary" href={roomCalendarUrl(filter,{date:shiftMonth(filter.date,1)})}>Következő →</Link></nav></div>
        <p className="muted">A sáv {timeLabel(data.opening.start)}–{timeLabel(data.opening.end)} között: zöld = szabad, sötét = foglalt. Koppints egy napra a részletekhez.</p>
        <div className={styles.grid}>{["H","K","Sze","Cs","P","Szo","V"].map(d=><div className={styles.weekday} key={d}>{d}</div>)}
          {monthGrid(filter.date).map(date=>{
            if (date.slice(0,7)!==filter.date.slice(0,7)) return <div className={styles.outside} key={date}>{Number(date.slice(8))}</div>;
            const bookings=grouped[date] ?? [], free=gapsByDate.get(date) ?? [];
            const matchesDay=!filter.weekday || String(new Date(`${date}T12:00:00Z`).getUTCDay())===filter.weekday;
            return <Link key={date} className={`${styles.day} ${date===filter.date?styles.selected:""} ${date===today?styles.today:""}`} href={roomCalendarUrl(filter,{date})} aria-label={`${dateLabel(date)}, ${bookings.length} foglalás, ${free.length} megfelelő szabad időszak`} aria-current={date===filter.date?"date":undefined}>
              <strong>{Number(date.slice(8))}</strong><div className={styles.bar} aria-hidden="true">{bookings.map(b=>{const m=bookingMinutes(b); const start=Math.max(m.start,data.opening.start),end=Math.min(m.end,data.opening.end); return end>start?<span key={b.booking_id} style={{left:`${100*(start-data.opening.start)/(data.opening.end-data.opening.start)}%`,width:`${100*(end-start)/(data.opening.end-data.opening.start)}%`}}/>:null;})}</div>
              <small className="muted">{bookings.length} foglalás</small>
              <small className={styles.free}>{!matchesDay?"Másik nap":free.length?`${timeLabel(free[0].start)}–${timeLabel(free[0].end)}`:"Nincs találat"}</small>{free.length>1?<small className={styles.more}>+{free.length-1} szabad sáv</small>:null}
            </Link>;
          })}
        </div>
      </section>
      <section className="card stack" aria-label="Kiválasztott nap részletei"><div className={styles.heading}><h2>{dateLabel(filter.date)}</h2><Link className="button secondary" href={`/foglalasok?datum=${filter.date}&room=${room.room_id}`}>Napi naptár</Link></div>
        <h3>Foglalások</h3>{selectedBookings.length?selectedBookings.map(b=><article className={styles.row} key={b.booking_id}><strong>{interval(b)}</strong><span>{owner(b)}{b.booking_title?` · ${b.booking_title}`:""}</span></article>):<p className="muted">Erre a napra nincs foglalás.</p>}
        <h3>Megfelelő szabad időpontok</h3>{selectedGaps.length?selectedGaps.map(slotRow):<p className="muted">Nincs a keresési feltételeknek megfelelő szabad időszak.</p>}
      </section>
    </> : <section className="card stack"><div className={styles.heading}><h2>{filter.kind === "free"?"Szabad időpontok":"Foglalások"}</h2><span className="muted">{resultCount} találat</span></div><p className="muted">{dateLabel(filter.from)} – {dateLabel(filter.to)}</p>
      {filter.kind === "free" ? gaps.slice(fromRow,fromRow+100).map(slotRow) : listBookings.slice(fromRow,fromRow+100).map(b=><article className={styles.row} key={b.booking_id}><div><strong>{dateLabel(budapestDateFromIso(b.start_at))}</strong><p>{interval(b)} · {owner(b)}</p>{b.booking_title?<span>{b.booking_title}</span>:null}</div><Link className="button secondary" href={`/foglalasok?datum=${budapestDateFromIso(b.start_at)}&room=${room.room_id}`}>Napi naptár</Link></article>)}
      {!resultCount?<p className="muted">A megadott feltételekkel nincs találat.</p>:null}
      {pages>1?<nav className={styles.tabs} aria-label="Találati oldalak">{page>1?<Link href={`${roomCalendarUrl(filter)}&page=${page-1}`}>← Előző</Link>:null}<span>{page}. / {pages}. oldal</span>{page<pages?<Link href={`${roomCalendarUrl(filter)}&page=${page+1}`}>Következő →</Link>:null}</nav>:null}
    </section>}
    <p className="muted">A szabad időpontok a lekérdezéskori állapotot mutatják. Foglaláskor a rendszer újra ellenőrzi az időpontot és a jogosultságot. <a href={roomCalendarUrl(filter)}>Frissítés</a></p>
  </section>;
}
