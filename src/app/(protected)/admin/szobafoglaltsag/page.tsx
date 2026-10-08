import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { loadRoomOccupancy } from "@/lib/room-occupancy-data";
import { dateLabel, filterQuery, freeMatches, parseOccupancyFilter, REPORT_PAGE_SIZE, shiftDay, timeLabel, timeMinutes, todayBudapest, visibleWeek, type OccupancyBooking, type ReportParams } from "@/lib/room-occupancy";
import { OccupancyFilters } from "./filters";
import styles from "./occupancy.module.css";

export const dynamic = "force-dynamic";
function bookingTime(b: OccupancyBooking) { return `${b.start_time.slice(0,5)}–${b.end_time.slice(0,5)}`; }
export default async function RoomOccupancyPage({ searchParams }: { searchParams: Promise<ReportParams> }) {
  await requireAdmin();
  const params = await searchParams, today = todayBudapest();
  let filter = parseOccupancyFilter({}, today), error: string | null = null;
  let data: Awaited<ReturnType<typeof loadRoomOccupancy>> | null = null;
  try { filter = parseOccupancyFilter(params, today); data = await loadRoomOccupancy(filter); }
  catch (e) { error = e instanceof Error ? e.message : "A lekérdezés nem sikerült. Próbáld újra."; }
  const days = visibleWeek(filter);
  const totalPages = Math.max(1, Math.ceil((data?.bookings.length ?? 0) / REPORT_PAGE_SIZE));
  const page = Math.min(filter.page, totalPages);
  const rows = data?.bookings.slice((page-1)*REPORT_PAGE_SIZE, page*REPORT_PAGE_SIZE) ?? [];
  const gaps = data && filter.view === "week" ? data.selectedRooms.flatMap(room => days.filter(d => d >= filter.from && d <= filter.to).flatMap(date => freeMatches(data.bookings, date, room, filter, data.opening).map(gap => ({room, date, ...gap})))) : [];
  return <section className={`stack ${styles.page}`}>
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Szobafoglaltság</h1><p className="muted">Keresd vissza a foglalásokat, vagy nézd meg, hol van szabad idő.</p></div></header>
    {data ? <OccupancyFilters key={filterQuery(filter)} filter={filter} rooms={data.rooms} users={data.users} today={today} /> : null}
    {error ? <div className="message error" role="alert"><p>{error}</p><Link href="/admin/szobafoglaltsag">Vissza az alap lekérdezéshez</Link></div> : null}
    {data && filter.view === "list" ? <section className="card wide-card stack">
      <div className={styles.resultHeading}><div><h2>Foglalási lista</h2><p>{dateLabel(filter.from)} – {dateLabel(filter.to)} · {data.bookings.length} találat</p></div><a className="button secondary" href={`/admin/szobafoglaltsag/export?${filterQuery(filter)}`}>Excel export</a></div>
      <div className={styles.tableScroll}><table><thead><tr><th>Dátum / nap</th><th>Időpont</th><th>Szoba</th><th>Foglaló</th><th>Foglalás megnevezése</th><th>Állapot</th></tr></thead><tbody>{rows.map(b => <tr key={b.booking_id}><td>{dateLabel(b.booking_date, true)}</td><td>{bookingTime(b)}</td><td>{b.room_name}</td><td>{b.user_name}</td><td>{b.booking_title ?? "–"}</td><td>{b.status === "cancelled" ? "Törölt" : "Aktív"}</td></tr>)}</tbody></table></div>
      <div className={styles.mobileList}>{rows.map(b => <article key={b.booking_id} className={styles.mobileBooking}><strong>{dateLabel(b.booking_date, true)}</strong><span>{bookingTime(b)} · {b.room_name}</span><span>{b.user_name}</span>{b.booking_title ? <span>{b.booking_title}</span> : null}{b.status === "cancelled" ? <strong>Törölt</strong> : null}</article>)}</div>
      {!rows.length ? <p className="muted">A megadott feltételekkel nincs foglalás.</p> : null}
      {totalPages > 1 ? <nav aria-label="Találati oldalak" className={styles.presets}>{page > 1 ? <Link className="button secondary" href={`?${filterQuery(filter, {page: page-1})}`}>← Előző</Link> : null}<span>{page}. / {totalPages}. oldal</span>{page < totalPages ? <Link className="button secondary" href={`?${filterQuery(filter, {page: page+1})}`}>Következő →</Link> : null}</nav> : null}
    </section> : null}
    {data && filter.view === "week" ? <>
      <section className="card wide-card stack"><div className={styles.resultHeading}><h2>{dateLabel(days[0])} – {dateLabel(days[6])}</h2><nav aria-label="Hetek" className={styles.presets}>{days[0] > filter.from ? <Link className="button secondary" href={`?${filterQuery(filter, {week: shiftDay(filter.week,-7)})}`}>← Előző hét</Link> : null}{days[6] < filter.to ? <Link className="button secondary" href={`?${filterQuery(filter, {week: shiftDay(filter.week,7)})}`}>Következő hét →</Link> : null}</nav></div>
        <p className="muted">Színes blokk: foglalt. Fehér: szabad a nyitvatartáson belül. A heti rács csak a kiválasztott dátumtartomány napjait mutatja; a törölt foglalások nem foglalnak helyet.</p>
        {data.selectedRooms.map(room => <section key={room.id} className={styles.roomWeek}><h3>{room.name}{!room.is_active ? " (inaktív)" : ""}</h3><div className={styles.weekScroll} tabIndex={0} role="region" aria-label={`${room.name} heti foglaltság`}>
          <div className={styles.weekGrid}>
            <div className={styles.corner}>Idő</div>{days.map(date => <div className={styles.dayHeading} key={date}>{dateLabel(date, true)}</div>)}
            <div className={styles.timeAxis} style={{height: (data.opening.end-data.opening.start)*.8}}>{Array.from({length: Math.ceil((data.opening.end-data.opening.start)/60)},(_,i) => data.opening.start+i*60).map(m => <span key={m} style={{top:(m-data!.opening.start)*.8}}>{timeLabel(m)}</span>)}<span style={{bottom:0}}>{timeLabel(data.opening.end)}</span></div>
            {days.map(date => { const inside = date >= filter.from && date <= filter.to; return <div key={date} className={`${styles.dayColumn} ${!inside ? styles.outside : ""}`} style={{height:(data.opening.end-data.opening.start)*.8}}>
              {!inside ? <p>A dátumszűrésen kívül</p> : data.bookings.filter(b => b.room_name === room.name && b.booking_date === date).map(b => {
                const start=Math.max(timeMinutes(b.start_time),data!.opening.start),end=Math.min(timeMinutes(b.end_time),data!.opening.end);
                if(end<=start)return null;
                return <div key={b.booking_id} className={styles.block} style={{top:(start-data!.opening.start)*.8,height:(end-start)*.8}} title={`${bookingTime(b)} · ${b.user_name}${b.booking_title ? ` · ${b.booking_title}` : ""}`}><strong>{bookingTime(b)}</strong><span>{b.user_name}</span>{b.booking_title ? <span>{b.booking_title}</span> : null}</div>;
              })}</div>; })}
          </div></div></section>)}
      </section>
      <section className="card wide-card stack"><h2>Szabad időpontok ezen a héten</h2><p>{timeLabel(filter.start)}–{timeLabel(filter.end)} között · {filter.whole ? "a teljes idősáv szabad" : `legalább ${(filter.duration/60).toLocaleString("hu-HU")} egybefüggő óra`} · {gaps.length} találat</p>
        {gaps.length ? <ul className={styles.freeList}>{gaps.map(g => <li key={`${g.room.id}-${g.date}-${g.start}`}><strong>{g.room.name}</strong><span>{dateLabel(g.date,true)}</span><span>{timeLabel(g.start)}–{timeLabel(g.end)} szabad</span></li>)}</ul> : <p className="muted">Nincs a feltételeknek megfelelő szabad időpont ezen a héten.</p>}
        <p className="muted">A lista a lekérdezés pillanatában szabad időket mutatja. Foglaláskor a rendszer újra ellenőrzi a jogosultságot és az ütközéseket.</p>
      </section>
    </> : null}
  </section>;
}
