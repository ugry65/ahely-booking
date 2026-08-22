import type { CSSProperties } from "react";
import Link from "next/link";
import { requireActiveProfile } from "@/lib/auth";
import { addDays, budapestTimeFromIso, budapestToday, civilDateLabel, groupBookingsByBudapestDate, isValidCivilDate, minutesFromTime, monthGrid, shiftMonth } from "@/lib/my-bookings-calendar";
import { createClient } from "@/lib/supabase/server";
import { BookingManagement, type BookableRoom, type MyBooking } from "./booking-management";
import styles from "./my-bookings.module.css";

type View = "day" | "month" | "list";
function paramValue(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function viewFromParam(value: string | undefined): View { return value === "day" || value === "list" ? value : "month"; }
function myBookingsUrl(view: View, date: string, bookingId?: string) { const params = new URLSearchParams({ view, date }); if (bookingId) params.set("booking", bookingId); return `/foglalasaim?${params.toString()}`; }
function dayLabel(date: string) { return civilDateLabel(date, { year: "numeric", month: "long", day: "numeric", weekday: "long" }); }
function monthLabel(date: string) { return civilDateLabel(date, { year: "numeric", month: "long" }); }
const weekDays = ["H", "K", "Sze", "Cs", "P", "Szo", "V"];

export default async function MyBookingsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireActiveProfile();
  const params = await searchParams;
  const view = viewFromParam(paramValue(params.view));
  const today = budapestToday();
  const requestedDate = paramValue(params.date);
  const selectedDate = isValidCivilDate(requestedDate) ? requestedDate : today;
  const selectedBookingId = paramValue(params.booking);
  const supabase = await createClient();
  const [bookingsResult, roomsResult] = await Promise.all([
    supabase.rpc("list_my_bookings").returns<MyBooking[]>(),
    supabase.rpc("list_bookable_rooms").returns<BookableRoom[]>(),
  ]);
  const bookings = ((bookingsResult.data ?? []) as unknown as MyBooking[]).sort((a, b) => a.start_at.localeCompare(b.start_at));
  const rooms = (roomsResult.data ?? []) as unknown as BookableRoom[];
  const grouped = groupBookingsByBudapestDate(bookings);
  const selectedDayBookings = grouped[selectedDate] ?? [];
  const selectedBooking = selectedBookingId ? bookings.find((booking) => booking.booking_id === selectedBookingId) : undefined;
  const returnTo = myBookingsUrl(view, selectedDate);

  return <section className={`stack ${styles.page}`}>
    <header className="page-heading"><div><p className="eyebrow">Saját időpontok</p><h1>Foglalásaim</h1><p className="muted">A jövőbeli aktív foglalásaid budapesti idő szerint.</p></div><Link className="button secondary" href="/foglalasok">Naptár és új foglalás</Link></header>
    {paramValue(params.hiba) || paramValue(params.uzenet) ? <p className={`message ${paramValue(params.hiba) ? "error" : "success"}`} role="status">{paramValue(params.hiba) ?? paramValue(params.uzenet)}</p> : null}
    {bookingsResult.error || roomsResult.error ? <p className="message error" role="alert">A foglalások betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : null}

    <div className={styles.controls}>
      <div className={styles.viewSwitch} role="navigation" aria-label="Foglalásaim nézet">
        {(["day", "month", "list"] as const).map((item) => <Link key={item} className={`${styles.viewLink} ${view === item ? styles.viewLinkActive : ""}`} href={myBookingsUrl(item, selectedDate)} aria-current={view === item ? "page" : undefined}>{item === "day" ? "Nap" : item === "month" ? "Hónap" : "Lista"}</Link>)}
      </div>
      <div className={styles.dateControls}>
        {view === "day" ? <><Link className={styles.navButton} aria-label="Előző nap" href={myBookingsUrl("day", addDays(selectedDate, -1))}>‹</Link><strong className={styles.periodLabel}>{dayLabel(selectedDate)}</strong><Link className={styles.navButton} aria-label="Következő nap" href={myBookingsUrl("day", addDays(selectedDate, 1))}>›</Link><Link className={styles.todayButton} href={myBookingsUrl("day", today)}>Ma</Link></> : null}
        {view === "month" ? <><Link className={styles.navButton} aria-label="Előző hónap" href={myBookingsUrl("month", shiftMonth(selectedDate, -1))}>‹</Link><strong className={styles.periodLabel}>{monthLabel(selectedDate)}</strong><Link className={styles.navButton} aria-label="Következő hónap" href={myBookingsUrl("month", shiftMonth(selectedDate, 1))}>›</Link><Link className={styles.todayButton} href={myBookingsUrl("month", today)}>Ma</Link></> : view === "list" ? <span className={styles.listDateHint}>Válassz dátumot a Nap nézetre ugráshoz.</span> : null}
        <form className={styles.datePicker} action="/foglalasaim" method="get"><input type="hidden" name="view" value={view === "list" ? "day" : view} /><label><span className={styles.srOnly}>Dátum kiválasztása</span><input name="date" type="date" required defaultValue={selectedDate} /></label><button type="submit">Mutasd</button></form>
      </div>
    </div>

    {selectedBooking ? <div className={styles.managementPanel}><BookingManagement booking={selectedBooking} rooms={rooms} returnTo={returnTo} closeHref={returnTo} /></div> : null}
    {!bookings.length && !bookingsResult.error ? <div className="card wide-card empty-state"><h2>Nincs közelgő foglalásod</h2><p className="muted">A naptárban hozhatsz létre új időpontot.</p></div> : null}
    {view === "month" ? <MonthView bookingsByDate={grouped} selectedDate={selectedDate} today={today} /> : null}
    {view === "day" ? <DayView bookings={selectedDayBookings} selectedDate={selectedDate} /> : null}
    {view === "list" ? <div className="my-bookings-list">{bookings.map((booking) => <BookingManagement key={booking.booking_id} booking={booking} rooms={rooms} returnTo={returnTo} />)}</div> : null}
  </section>;
}

function MonthView({ bookingsByDate, selectedDate, today }: { bookingsByDate: Record<string, MyBooking[]>; selectedDate: string; today: string }) {
  const days = monthGrid(selectedDate); const currentMonth = selectedDate.slice(0, 7); const selectedBookings = bookingsByDate[selectedDate] ?? [];
  return <div className={styles.monthSection}>
    <div className={styles.monthGrid}>{weekDays.map((day) => <div key={day} className={styles.weekday}>{day}</div>)}{days.map((date) => {
      const bookings = bookingsByDate[date] ?? []; const outOfMonth = date.slice(0, 7) !== currentMonth; const classes = [styles.monthCell, outOfMonth ? styles.outOfMonth : "", date === today ? styles.today : "", date === selectedDate ? styles.selectedDay : ""].filter(Boolean).join(" ");
      return <div className={classes} key={date}><Link className={styles.daySelect} href={myBookingsUrl("month", date)} aria-label={`${date}, ${bookings.length} foglalás`}><span className={styles.dayNumber}>{Number(date.slice(-2))}</span>{bookings.length ? <span className={styles.mobileBookingCount}>{bookings.length}</span> : null}</Link><div className={styles.desktopBookings}>{bookings.slice(0, 3).map((booking) => <Link key={booking.booking_id} className={styles.monthBooking} href={myBookingsUrl("month", date, booking.booking_id)}><strong>{budapestTimeFromIso(booking.start_at)}</strong> {booking.room_name}{booking.booking_title ? ` · ${booking.booking_title}` : ""}</Link>)}{bookings.length > 3 ? <Link className={styles.moreBookings} href={myBookingsUrl("month", date)}>+{bookings.length - 3} további</Link> : null}</div></div>;
    })}</div>
    <div className={styles.mobileSelectedDay}><h2>{dayLabel(selectedDate)}</h2>{!selectedBookings.length ? <p className="muted">Erre a napra nincs közelgő foglalásod.</p> : <div className={styles.mobileDayList}>{selectedBookings.map((booking) => <Link className={styles.mobileDayBooking} key={booking.booking_id} href={myBookingsUrl("month", selectedDate, booking.booking_id)}><strong>{budapestTimeFromIso(booking.start_at)}–{budapestTimeFromIso(booking.end_at)}</strong><span>{booking.room_name}{booking.booking_title ? ` · ${booking.booking_title}` : ""}</span></Link>)}</div>}</div>
  </div>;
}

function DayView({ bookings, selectedDate }: { bookings: MyBooking[]; selectedDate: string }) {
  const openingMinutes = 7 * 60; const closingMinutes = 22 * 60; const totalMinutes = closingMinutes - openingMinutes;
  const hourLabels = Array.from({ length: 16 }, (_, index) => 7 + index); const halfHourLines = Array.from({ length: 31 }, (_, index) => index * 30);
  return <div className={styles.dayCard}><h2 className={styles.dayHeading}>{dayLabel(selectedDate)}</h2>{!bookings.length ? <p className={`muted ${styles.dayEmpty}`}>Erre a napra nincs közelgő foglalásod.</p> : null}<div className={styles.dayTimelineWrap}><div className={styles.dayAxis} style={{ height: `${totalMinutes}px` }}>{hourLabels.map((hour, index) => <span key={hour} style={{ top: `${index * 60}px` }}>{String(hour).padStart(2, "0")}:00</span>)}</div><div className={styles.dayTimeline} style={{ height: `${totalMinutes}px` }}>{halfHourLines.map((offset) => <span key={offset} className={offset % 60 === 0 ? styles.hourLine : styles.halfHourLine} style={{ top: `${offset}px` }} />)}{bookings.map((booking) => {
    const start = minutesFromTime(budapestTimeFromIso(booking.start_at)); const end = minutesFromTime(budapestTimeFromIso(booking.end_at)); const top = Math.max(0, start - openingMinutes); const height = Math.max(44, Math.min(closingMinutes, end) - Math.max(openingMinutes, start)); const bookingStyle: CSSProperties = { top: `${top}px`, height: `${height}px` };
    return <Link key={booking.booking_id} className={styles.dayBooking} style={bookingStyle} href={myBookingsUrl("day", selectedDate, booking.booking_id)}><strong>{booking.room_name}</strong><span>{budapestTimeFromIso(booking.start_at)}–{budapestTimeFromIso(booking.end_at)} · {booking.use_type === "group" ? "Csoportos" : "Egyéni"}{booking.booking_title ? ` · ${booking.booking_title}` : ""}</span></Link>;
  })}</div></div></div>;
}
