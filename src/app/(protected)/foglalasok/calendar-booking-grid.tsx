"use client";

import { useEffect, useMemo, useRef, useState, type PointerEvent } from "react";
import { createPortal } from "react-dom";
import { cancelCalendarBooking, createBooking, updateCalendarBooking } from "./actions";
import { createRecurringBooking } from "./ismetlod/actions";
import { CALENDAR_CLOSE_MINUTE, CALENDAR_OPEN_MINUTE, calendarMinuteToTime, normalizeCalendarSelection, type CalendarSelection } from "@/lib/calendar-selection";
import { BookingTimeFields } from "./booking-time-fields";
import { RecurringExceptionCalendar } from "./ismetlod/recurring-exception-calendar";

export type BookableRoom = { room_id: string; room_name: string; is_training_room: boolean; display_order: number };
export type CalendarBooking = {
  booking_id: string; room_id: string; room_name: string; start_at: string; end_at: string;
  use_type: "individual" | "group"; is_own: boolean; booker_display_name: string | null; booker_color: string | null;
  booking_title: string | null; note: string | null; series_id: string | null; updated_at: string | null; can_manage: boolean;
};
type Props = { rooms: BookableRoom[]; bookings: CalendarBooking[]; selectedDate: string; repeatableRoomIds: string[]; bookingUsers?: Array<{ id: string; name: string; email: string }>; currentUserId?: string; isAdmin?: boolean };
type TouchGesture = { roomId: string; pointerId: number; startX: number; startY: number; anchorMinute: number; active: boolean; element: HTMLDivElement };
type RepeatFrequency = "none" | "daily" | "weekly" | "biweekly" | "monthly";
type BookingScope = "occurrence" | "following" | "series";
type DialogMode = "create" | "duplicate" | "edit";

const PIXELS_PER_MINUTE = 2 / 3;
const TIMELINE_HEIGHT = (CALENDAR_CLOSE_MINUTE - CALENDAR_OPEN_MINUTE) * PIXELS_PER_MINUTE;
const minuteToPixel = (minute: number) => minute * PIXELS_PER_MINUTE;
const LONG_PRESS_MS = 500;
const TOUCH_MOVE_CANCEL_PX = 10;

function localMinute(iso: string) {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Budapest", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(iso));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return Number(values.hour) * 60 + Number(values.minute);
}
function timeOptions() {
  const values: string[] = [];
  for (let minute = CALENDAR_OPEN_MINUTE; minute <= CALENDAR_CLOSE_MINUTE; minute += 30) values.push(calendarMinuteToTime(minute));
  return values;
}

export function CalendarBookingGrid({ rooms, bookings, selectedDate, repeatableRoomIds, bookingUsers = [], currentUserId, isAdmin = false }: Props) {
  const [selection, setSelection] = useState<CalendarSelection | null>(null);
  const [bookingDialogOpen, setBookingDialogOpen] = useState(false);
  const [dialogRoomId, setDialogRoomId] = useState("");
  const [repeatFrequency, setRepeatFrequency] = useState<RepeatFrequency>("none");
  const [useType, setUseType] = useState<"individual" | "group">("individual");
  const [dialogMode, setDialogMode] = useState<DialogMode>("create");
  const [sourceBooking, setSourceBooking] = useState<CalendarBooking | null>(null);
  const [editScope, setEditScope] = useState<BookingScope>("occurrence");
  const [menuBooking, setMenuBooking] = useState<CalendarBooking | null>(null);
  const [scopePrompt, setScopePrompt] = useState<{ kind: "edit" | "cancel"; booking: CalendarBooking } | null>(null);
  const [cancelTarget, setCancelTarget] = useState<{ booking: CalendarBooking; scope: BookingScope } | null>(null);
  const [selectionActionHost, setSelectionActionHost] = useState<HTMLElement | null>(null);
  const dragState = useRef<{ roomId: string; anchorMinute: number } | null>(null);
  const touchGesture = useRef<TouchGesture | null>(null);
  const longPressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const idempotencyKey = useMemo(() => crypto.randomUUID(), [selection?.roomId, selection?.startMinute, selection?.endMinute, repeatFrequency, dialogMode, editScope, cancelTarget?.booking.booking_id, cancelTarget?.scope]);

  useEffect(() => {
    setSelectionActionHost(document.getElementById("calendar-selection-actions-slot"));
  }, []);

  function minuteFromPointer(element: HTMLElement, clientY: number) { const rect = element.getBoundingClientRect(); return CALENDAR_OPEN_MINUTE + (clientY - rect.top) / PIXELS_PER_MINUTE; }
  function cancelLongPress() { if (longPressTimer.current) { clearTimeout(longPressTimer.current); longPressTimer.current = null; } }
  function activateSelection(roomId: string, element: HTMLDivElement, pointerId: number, anchorMinute: number) {
    setMenuBooking(null); setSourceBooking(null); setDialogMode("create"); setBookingDialogOpen(false); setDialogRoomId(roomId); setRepeatFrequency("none"); setUseType("individual");
    element.setPointerCapture(pointerId); dragState.current = { roomId, anchorMinute }; setSelection(normalizeCalendarSelection(roomId, anchorMinute, anchorMinute));
  }
  function beginSelection(roomId: string, event: PointerEvent<HTMLDivElement>) {
    if ((event.target as HTMLElement).closest(".booking-block")) return;
    const anchorMinute = minuteFromPointer(event.currentTarget, event.clientY);
    if (event.pointerType === "touch") {
      cancelLongPress(); touchGesture.current = { roomId, pointerId: event.pointerId, startX: event.clientX, startY: event.clientY, anchorMinute, active: false, element: event.currentTarget };
      longPressTimer.current = setTimeout(() => { const gesture = touchGesture.current; if (!gesture || gesture.pointerId !== event.pointerId) return; gesture.active = true; activateSelection(gesture.roomId, gesture.element, gesture.pointerId, gesture.anchorMinute); }, LONG_PRESS_MS); return;
    }
    event.preventDefault(); activateSelection(roomId, event.currentTarget, event.pointerId, anchorMinute);
  }
  function moveSelection(roomId: string, event: PointerEvent<HTMLDivElement>) {
    if (event.pointerType === "touch") {
      const gesture = touchGesture.current; if (!gesture || gesture.pointerId !== event.pointerId || gesture.roomId !== roomId) return;
      if (!gesture.active) { if (Math.hypot(event.clientX - gesture.startX, event.clientY - gesture.startY) > TOUCH_MOVE_CANCEL_PX) { cancelLongPress(); touchGesture.current = null; } return; }
      event.preventDefault();
    }
    const drag = dragState.current; if (!drag || drag.roomId !== roomId) return;
    setSelection(normalizeCalendarSelection(roomId, drag.anchorMinute, minuteFromPointer(event.currentTarget, event.clientY)));
  }
  function endSelection(event?: PointerEvent<HTMLDivElement>) {
    cancelLongPress(); const completedTouchSelection = event?.pointerType === "touch" && touchGesture.current?.active === true;
    if (event?.pointerType === "touch") touchGesture.current = null; dragState.current = null; if (completedTouchSelection) setBookingDialogOpen(true);
  }
  function clearSelection() { cancelLongPress(); touchGesture.current = null; setBookingDialogOpen(false); setDialogRoomId(""); setRepeatFrequency("none"); setUseType("individual"); setSelection(null); setSourceBooking(null); setDialogMode("create"); }
  function setSelectionFromBooking(booking: CalendarBooking) { setSelection(normalizeCalendarSelection(booking.room_id, localMinute(booking.start_at), localMinute(booking.end_at))); setDialogRoomId(booking.room_id); setRepeatFrequency("none"); setUseType(booking.use_type); setSourceBooking(booking); }
  function duplicateBooking(booking: CalendarBooking) { setMenuBooking(null); setSelectionFromBooking(booking); setDialogMode("duplicate"); setBookingDialogOpen(true); }
  function editBooking(booking: CalendarBooking, scope: BookingScope) { setMenuBooking(null); setScopePrompt(null); setSelectionFromBooking(booking); setEditScope(scope); setDialogMode("edit"); setBookingDialogOpen(true); }
  function requestEdit(booking: CalendarBooking) { setMenuBooking(null); if (booking.series_id) setScopePrompt({ kind: "edit", booking }); else editBooking(booking, "occurrence"); }
  function requestCancel(booking: CalendarBooking) { setMenuBooking(null); if (booking.series_id) setScopePrompt({ kind: "cancel", booking }); else setCancelTarget({ booking, scope: "occurrence" }); }
  function chooseScope(scope: BookingScope) { if (!scopePrompt) return; if (scopePrompt.kind === "edit") editBooking(scopePrompt.booking, scope); else { setCancelTarget({ booking: scopePrompt.booking, scope }); setScopePrompt(null); } }

  const selectedRoom = selection ? rooms.find((room) => room.room_id === selection.roomId) : null;
  const dialogRoom = rooms.find((room) => room.room_id === dialogRoomId) ?? selectedRoom;
  const options = timeOptions();
  const canRepeat = dialogRoom ? repeatableRoomIds.includes(dialogRoom.room_id) : false;
  const formAction = dialogMode === "edit" ? updateCalendarBooking : repeatFrequency === "none" ? createBooking : createRecurringBooking;
  const modalTitle = dialogMode === "edit" ? "Foglalás szerkesztése" : dialogMode === "duplicate" ? "Foglalás duplikálása" : "Foglalás";
  const roomMinWidth = rooms.length >= 11 ? "8rem" : "8.75rem";
  const showGroupRate = isAdmin && dialogMode !== "edit" && dialogRoom?.is_training_room && useType === "group";

  return <div className="calendar-workspace stack">
    <div className="calendar-card" aria-label={`${selectedDate} foglalásai`}><div className="calendar-scroll"><div className="calendar-grid" style={{ gridTemplateColumns: `4.25rem repeat(${rooms.length}, minmax(${roomMinWidth}, 1fr))`, width: "max(100%, max-content)" }}>
      <div className="calendar-corner" />
      {rooms.map((room) => <div className="room-heading" key={room.room_id} style={{ minWidth: roomMinWidth }}>{room.room_name}</div>)}
      <div className="time-axis" style={{ height: `${TIMELINE_HEIGHT}px` }}>
        {Array.from({ length: 16 }, (_, index) => <div aria-hidden="true" className="time-axis-hour-line" key={`line-${index}`} style={{ top: `${minuteToPixel(index * 60)}px` }} />)}
        {Array.from({ length: 15 }, (_, index) => <span key={`label-${index}`} style={{ top: `${minuteToPixel(index * 60 + 30)}px` }}>{String(index + 7).padStart(2, "0")}:00</span>)}
      </div>
      {rooms.map((room) => <div className="room-timeline" key={room.room_id} style={{ height: `${TIMELINE_HEIGHT}px`, cursor: "crosshair", touchAction: "auto" }} onPointerDown={(event) => beginSelection(room.room_id, event)} onPointerMove={(event) => moveSelection(room.room_id, event)} onPointerUp={(event) => endSelection(event)} onPointerCancel={(event) => endSelection(event)} onContextMenu={(event) => event.preventDefault()} aria-label={`${room.room_name} szabad időpontjai. Asztali gépen húzással, mobilon hosszan nyomva indítható foglalás.`}>
        {selection?.roomId === room.room_id && !sourceBooking ? <div className="selection-block" style={{ top: `${minuteToPixel(selection.startMinute - CALENDAR_OPEN_MINUTE)}px`, height: `${minuteToPixel(selection.endMinute - selection.startMinute)}px` }}><strong>{calendarMinuteToTime(selection.startMinute)}–{calendarMinuteToTime(selection.endMinute)}</strong><span>Új foglalás</span></div> : null}
        {bookings.filter((booking) => booking.room_id === room.room_id).map((booking) => {
          const start = Math.max(localMinute(booking.start_at), CALENDAR_OPEN_MINUTE); const end = Math.min(localMinute(booking.end_at), CALENDAR_CLOSE_MINUTE);
          const colorStyle = booking.booker_color ? { borderLeftColor: booking.booker_color, background: `color-mix(in srgb, ${booking.booker_color} 18%, white)` } : {};
          return <article role={booking.can_manage ? "button" : undefined} tabIndex={booking.can_manage ? 0 : undefined} className={`booking-block ${booking.is_own ? "own" : ""} ${booking.can_manage ? "manageable" : ""}`} key={booking.booking_id} style={{ top: `${minuteToPixel(start - CALENDAR_OPEN_MINUTE)}px`, height: `${Math.max(minuteToPixel(end - start), minuteToPixel(30))}px`, ...colorStyle }} onPointerDown={(event) => event.stopPropagation()} onClick={(event) => { event.stopPropagation(); if (booking.can_manage) setMenuBooking(booking); }} onKeyDown={(event) => { if (booking.can_manage && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); setMenuBooking(booking); } }}>
            <span><strong>{booking.is_own ? "Saját foglalás" : booking.booker_display_name ?? "Foglalt"}</strong>{booking.booking_title ? <> · {booking.booking_title}</> : null}</span>
            {booking.use_type === "group" ? <small>Csoportos</small> : null}
          </article>;
        })}
      </div>)}
    </div></div></div>

    {selection && selectedRoom && !sourceBooking && selectionActionHost ? createPortal(<div className="selection-action-bar" aria-live="polite"><span style={{ fontWeight: 700 }}>{selectedRoom.room_name} · {calendarMinuteToTime(selection.startMinute)}–{calendarMinuteToTime(selection.endMinute)}</span><button type="button" className="button secondary" onClick={clearSelection}>Mégse</button><button type="button" onClick={() => setBookingDialogOpen(true)}>Foglalás</button></div>, selectionActionHost) : null}

    {menuBooking ? <div className="booking-action-backdrop" onClick={() => setMenuBooking(null)}><div className="booking-action-popover" role="menu" aria-label="Foglalási műveletek" onClick={(event) => event.stopPropagation()}><button type="button" className="booking-action-item" onClick={() => requestEdit(menuBooking)}>✎ Szerkesztés</button><button type="button" className="booking-action-item" onClick={() => duplicateBooking(menuBooking)}>⧉ Duplikálás</button><button type="button" className="booking-action-item danger-action" onClick={() => requestCancel(menuBooking)}>⌫ Törlés</button></div></div> : null}

    {scopePrompt ? <div className="booking-modal-backdrop" role="dialog" aria-modal="true" aria-label="Sorozat hatókörének kiválasztása"><section className="card stack booking-modal-card scope-choice-card"><div className="booking-modal-heading"><div><p className="eyebrow">Ismétlődő foglalás</p><h2>{scopePrompt.kind === "edit" ? "Mit szeretnél szerkeszteni?" : "Mit szeretnél törölni?"}</h2></div><button type="button" className="button secondary" onClick={() => setScopePrompt(null)}>×</button></div><button type="button" className="button secondary scope-choice" onClick={() => chooseScope("occurrence")}>Csak ezt az alkalmat</button><button type="button" className="button secondary scope-choice" onClick={() => chooseScope("following")}>Ezt és az ezt követő alkalmakat</button><button type="button" className="button secondary scope-choice" onClick={() => chooseScope("series")}>A teljes sorozatot</button><p className="muted form-help">A már lezajlott alkalmak történeti adatai nem módosulnak és nem törlődnek.</p></section></div> : null}

    {selection && selectedRoom && bookingDialogOpen ? <div role="dialog" aria-modal="true" aria-labelledby="selection-booking-title" className="booking-modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) clearSelection(); }}><section className="card stack booking-modal-card"><div className="booking-modal-heading"><div><p className="eyebrow">{dialogMode === "edit" ? "Meglévő időpont" : dialogMode === "duplicate" ? "Másolat" : "Új időpont"}</p><h2 id="selection-booking-title">{modalTitle}</h2></div><button type="button" className="button secondary" onClick={clearSelection} aria-label="Bezárás">×</button></div>
      <form key={`${dialogMode}-${sourceBooking?.booking_id ?? "new"}-${editScope}`} action={formAction} className="stack">
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        {dialogMode === "edit" && sourceBooking ? <><input type="hidden" name="bookingId" value={sourceBooking.booking_id} /><input type="hidden" name="expectedUpdatedAt" value={sourceBooking.updated_at ?? ""} /><input type="hidden" name="scope" value={editScope} /></> : null}
        {dialogMode !== "edit" && bookingUsers.length ? <label>Felhasználó<select name="targetUserId" defaultValue={currentUserId ?? bookingUsers[0]?.id} required>{bookingUsers.map((user) => <option key={user.id} value={user.id}>{user.name} · {user.email}</option>)}</select><span className="muted form-help">Adminisztrátorként kiválaszthatod, kinek a nevében jön létre a foglalás.</span></label> : null}
        <label>Helyiség<select name="roomId" value={dialogRoomId || selection.roomId} onChange={(event) => { setDialogRoomId(event.target.value); setRepeatFrequency("none"); setUseType("individual"); }} required>{rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}</select></label>
        <label>Dátum<input name="date" type="date" defaultValue={selectedDate} required /></label>
        <BookingTimeFields options={options} initialStartTime={calendarMinuteToTime(selection.startMinute)} initialEndTime={calendarMinuteToTime(selection.endMinute)} />
        {dialogMode !== "edit" ? <label>Ismétlődés<select name="frequency" value={repeatFrequency} onChange={(event) => setRepeatFrequency(event.target.value as RepeatFrequency)} disabled={!canRepeat}><option value="none">Nincs</option><option value="daily">Naponta</option><option value="weekly">Hetente</option><option value="biweekly">Kéthetente</option><option value="monthly">Havonta</option></select>{!canRepeat ? <span className="muted form-help">Ehhez a helyiséghez nincs ismétlődő foglalási jogosultságod.</span> : null}</label> : null}
        {dialogMode !== "edit" && repeatFrequency !== "none" ? <fieldset className="repeat-options"><legend>Ismétlődés beállításai</legend><input type="hidden" name="endMode" value="count" /><label>Alkalmak száma<input name="occurrenceCount" type="number" min="1" max="400" defaultValue="6" required /></label><RecurringExceptionCalendar /><label>Ütközés kezelése<select name="conflictPolicy" defaultValue="abort_all"><option value="abort_all">Teljes sorozat megszakítása</option><option value="create_available">Csak a szabad alkalmak létrehozása</option></select></label></fieldset> : null}
        {dialogRoom?.is_training_room ? <label>Használat<select name="useType" value={useType} onChange={(event) => setUseType(event.target.value as "individual" | "group")}><option value="individual">Egyéni</option><option value="group">Csoportos</option></select></label> : <input type="hidden" name="useType" value="individual" />}
        {showGroupRate ? <label>Csoportos óradíj<input name="groupHourlyRateHuf" type="number" min="0" step="1" defaultValue="5000" required /><span className="muted form-help">Alapértelmezett díj: 5 000 Ft/óra. Adminisztrátorként ennél a foglalásnál vagy sorozatnál felülírhatod.</span></label> : null}
        <label>Foglalás címe<input name="bookingTitle" maxLength={100} defaultValue={sourceBooking?.booking_title ?? ""} placeholder="Opcionális" /></label>
        <span className="muted form-help">A címet csak a foglalás tulajdonosa és az adminisztrátorok láthatják.</span>
        <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} defaultValue={sourceBooking?.note ?? ""} placeholder="Opcionális" /></label>
        {dialogMode === "edit" && sourceBooking?.series_id ? <p className="message">Hatókör: {editScope === "occurrence" ? "csak ez az alkalom" : editScope === "following" ? "ez és a következő alkalmak" : "teljes jövőbeli sorozat"}.</p> : null}
        <div className="booking-modal-actions"><button type="submit">{dialogMode === "edit" ? "Módosítás mentése" : repeatFrequency === "none" ? "Foglalás mentése" : "Sorozat létrehozása"}</button><button type="button" className="button secondary" onClick={clearSelection}>Mégse</button></div>
        <p className="muted form-help">A mentéskor a backend újra ellenőrzi a jogosultságot, az előrefoglalási limitet és az ütközést.</p>
      </form></section></div> : null}

    {cancelTarget ? <div role="dialog" aria-modal="true" aria-label="Foglalás törlése" className="booking-modal-backdrop"><section className="card stack booking-modal-card"><div className="booking-modal-heading"><div><p className="eyebrow">Törlés</p><h2>{cancelTarget.booking.series_id ? "Ismétlődő foglalás törlése" : "Foglalás törlése"}</h2></div><button type="button" className="button secondary" onClick={() => setCancelTarget(null)}>×</button></div><p>Biztosan törlöd {cancelTarget.scope === "occurrence" ? "ezt az alkalmat" : cancelTarget.scope === "following" ? "ezt és az ezt követő alkalmakat" : "a teljes jövőbeli sorozatot"}?</p><form action={cancelCalendarBooking} className="stack"><input type="hidden" name="bookingId" value={cancelTarget.booking.booking_id} /><input type="hidden" name="scope" value={cancelTarget.scope} /><input type="hidden" name="date" value={selectedDate} /><input type="hidden" name="idempotencyKey" value={idempotencyKey} /><label>Indok<textarea name="reason" maxLength={500} rows={2} placeholder="Opcionális" /></label><div className="booking-modal-actions"><button type="submit" className="danger-button">Törlés megerősítése</button><button type="button" className="button secondary" onClick={() => setCancelTarget(null)}>Mégse</button></div></form></section></div> : null}

    {!selection ? <p className="muted calendar-help">Asztali gépen húzással, mobilon hosszan nyomva jelölhetsz ki foglalási időszakot.</p> : null}
  </div>;
}
