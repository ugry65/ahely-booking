"use client";

import { useMemo, useRef, useState, type PointerEvent } from "react";
import { createBooking } from "./actions";
import {
  CALENDAR_CLOSE_MINUTE,
  CALENDAR_OPEN_MINUTE,
  calendarMinuteToTime,
  normalizeCalendarSelection,
  type CalendarSelection,
} from "@/lib/calendar-selection";

export type BookableRoom = {
  room_id: string;
  room_name: string;
  is_training_room: boolean;
  display_order: number;
};

export type CalendarBooking = {
  booking_id: string;
  room_id: string;
  room_name: string;
  start_at: string;
  end_at: string;
  use_type: "individual" | "group";
  is_own: boolean;
  booker_display_name: string | null;
};

type Props = {
  rooms: BookableRoom[];
  bookings: CalendarBooking[];
  selectedDate: string;
};

type TouchGesture = {
  roomId: string;
  pointerId: number;
  startX: number;
  startY: number;
  anchorMinute: number;
  active: boolean;
  element: HTMLDivElement;
};

const PIXELS_PER_MINUTE = 2 / 3;
const TIMELINE_HEIGHT = (CALENDAR_CLOSE_MINUTE - CALENDAR_OPEN_MINUTE) * PIXELS_PER_MINUTE;
const minuteToPixel = (minute: number) => minute * PIXELS_PER_MINUTE;
const LONG_PRESS_MS = 500;
const TOUCH_MOVE_CANCEL_PX = 10;

function localMinute(iso: string) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Budapest",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(iso));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return Number(values.hour) * 60 + Number(values.minute);
}

function timeLabel(iso: string) {
  return new Intl.DateTimeFormat("hu-HU", {
    timeZone: "Europe/Budapest",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(iso));
}

function timeOptions() {
  const values: string[] = [];
  for (let minute = CALENDAR_OPEN_MINUTE; minute <= CALENDAR_CLOSE_MINUTE; minute += 30) {
    values.push(calendarMinuteToTime(minute));
  }
  return values;
}

export function CalendarBookingGrid({ rooms, bookings, selectedDate }: Props) {
  const [selection, setSelection] = useState<CalendarSelection | null>(null);
  const [bookingDialogOpen, setBookingDialogOpen] = useState(false);
  const [dialogRoomId, setDialogRoomId] = useState("");
  const dragState = useRef<{ roomId: string; anchorMinute: number } | null>(null);
  const touchGesture = useRef<TouchGesture | null>(null);
  const longPressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const idempotencyKey = useMemo(
    () => crypto.randomUUID(),
    [selection?.roomId, selection?.startMinute, selection?.endMinute],
  );

  function minuteFromPointer(element: HTMLElement, clientY: number) {
    const rect = element.getBoundingClientRect();
    return CALENDAR_OPEN_MINUTE + (clientY - rect.top) / PIXELS_PER_MINUTE;
  }

  function cancelLongPress() {
    if (longPressTimer.current) {
      clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }
  }

  function activateSelection(roomId: string, element: HTMLDivElement, pointerId: number, anchorMinute: number) {
    setBookingDialogOpen(false);
    setDialogRoomId(roomId);
    element.setPointerCapture(pointerId);
    dragState.current = { roomId, anchorMinute };
    setSelection(normalizeCalendarSelection(roomId, anchorMinute, anchorMinute));
  }

  function beginSelection(roomId: string, event: PointerEvent<HTMLDivElement>) {
    if ((event.target as HTMLElement).closest(".booking-block")) return;

    const anchorMinute = minuteFromPointer(event.currentTarget, event.clientY);

    if (event.pointerType === "touch") {
      cancelLongPress();
      touchGesture.current = {
        roomId,
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        anchorMinute,
        active: false,
        element: event.currentTarget,
      };
      longPressTimer.current = setTimeout(() => {
        const gesture = touchGesture.current;
        if (!gesture || gesture.pointerId !== event.pointerId) return;
        gesture.active = true;
        activateSelection(gesture.roomId, gesture.element, gesture.pointerId, gesture.anchorMinute);
      }, LONG_PRESS_MS);
      return;
    }

    event.preventDefault();
    activateSelection(roomId, event.currentTarget, event.pointerId, anchorMinute);
  }

  function moveSelection(roomId: string, event: PointerEvent<HTMLDivElement>) {
    if (event.pointerType === "touch") {
      const gesture = touchGesture.current;
      if (!gesture || gesture.pointerId !== event.pointerId || gesture.roomId !== roomId) return;

      if (!gesture.active) {
        const dx = event.clientX - gesture.startX;
        const dy = event.clientY - gesture.startY;
        if (Math.hypot(dx, dy) > TOUCH_MOVE_CANCEL_PX) {
          cancelLongPress();
          touchGesture.current = null;
        }
        return;
      }

      event.preventDefault();
    }

    const drag = dragState.current;
    if (!drag || drag.roomId !== roomId) return;
    setSelection(normalizeCalendarSelection(roomId, drag.anchorMinute, minuteFromPointer(event.currentTarget, event.clientY)));
  }

  function endSelection(event?: PointerEvent<HTMLDivElement>) {
    cancelLongPress();
    const completedTouchSelection = event?.pointerType === "touch" && touchGesture.current?.active === true;
    if (event?.pointerType === "touch") touchGesture.current = null;
    dragState.current = null;
    if (completedTouchSelection) setBookingDialogOpen(true);
  }

  function clearSelection() {
    cancelLongPress();
    touchGesture.current = null;
    setBookingDialogOpen(false);
    setDialogRoomId("");
    setSelection(null);
  }

  const selectedRoom = selection ? rooms.find((room) => room.room_id === selection.roomId) : null;
  const dialogRoom = rooms.find((room) => room.room_id === dialogRoomId) ?? selectedRoom;
  const options = timeOptions();

  return (
    <div className="calendar-workspace stack">
      <div className="calendar-card" aria-label={`${selectedDate} foglalásai`}>
        <div className="calendar-scroll">
          <div
            className="calendar-grid"
            style={{
              gridTemplateColumns: `4.25rem repeat(${rooms.length}, minmax(8.75rem, 1fr))`,
              width: "max(100%, max-content)",
            }}
          >
            <div className="calendar-corner" />
            {rooms.map((room) => (
              <div className="room-heading" key={room.room_id} style={{ minWidth: "8.75rem" }}>
                {room.room_name}
                {room.is_training_room ? <small>Tréningterem</small> : null}
              </div>
            ))}

            <div className="time-axis" style={{ height: `${TIMELINE_HEIGHT}px` }}>
              {Array.from({ length: 16 }, (_, index) => (
                <span key={index} style={{ top: `${minuteToPixel(index * 60)}px` }}>{String(index + 7).padStart(2, "0")}:00</span>
              ))}
            </div>

            {rooms.map((room) => (
              <div
                className="room-timeline"
                key={room.room_id}
                style={{ height: `${TIMELINE_HEIGHT}px`, cursor: "crosshair", touchAction: "auto" }}
                onPointerDown={(event) => beginSelection(room.room_id, event)}
                onPointerMove={(event) => moveSelection(room.room_id, event)}
                onPointerUp={(event) => endSelection(event)}
                onPointerCancel={(event) => endSelection(event)}
                onContextMenu={(event) => event.preventDefault()}
                aria-label={`${room.room_name} szabad időpontjai. Asztali gépen húzással, mobilon hosszan nyomva indítható foglalás.`}
              >
                {selection?.roomId === room.room_id ? (
                  <div
                    style={{
                      position: "absolute",
                      left: ".2rem",
                      right: ".2rem",
                      zIndex: 2,
                      top: `${minuteToPixel(selection.startMinute - CALENDAR_OPEN_MINUTE)}px`,
                      height: `${minuteToPixel(selection.endMinute - selection.startMinute)}px`,
                      padding: ".25rem .4rem",
                      border: "2px solid #235c43",
                      borderRadius: ".35rem",
                      background: "rgb(220 235 226 / 88%)",
                      color: "#183c2c",
                      pointerEvents: "none",
                      display: "flex",
                      flexDirection: "column",
                      fontSize: ".72rem",
                    }}
                  >
                    <strong>{calendarMinuteToTime(selection.startMinute)}–{calendarMinuteToTime(selection.endMinute)}</strong>
                    <span>Új foglalás</span>
                  </div>
                ) : null}

                {bookings.filter((booking) => booking.room_id === room.room_id).map((booking) => {
                  const start = Math.max(localMinute(booking.start_at), CALENDAR_OPEN_MINUTE);
                  const end = Math.min(localMinute(booking.end_at), CALENDAR_CLOSE_MINUTE);
                  return (
                    <article
                      className={`booking-block ${booking.is_own ? "own" : ""}`}
                      key={booking.booking_id}
                      style={{
                        top: `${minuteToPixel(start - CALENDAR_OPEN_MINUTE)}px`,
                        height: `${Math.max(minuteToPixel(end - start), minuteToPixel(30))}px`,
                      }}
                      onPointerDown={(event) => event.stopPropagation()}
                    >
                      <strong>{timeLabel(booking.start_at)}–{timeLabel(booking.end_at)}</strong>
                      <span>{booking.is_own ? "Saját foglalás" : booking.booker_display_name ?? "Foglalt"}</span>
                      {booking.use_type === "group" ? <small>Csoportos</small> : null}
                    </article>
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      </div>

      {selection && selectedRoom ? (
        <div className="selection-action-bar" aria-live="polite">
          <span style={{ padding: "0 .45rem", fontWeight: 700 }}>
            {selectedRoom.room_name} · {calendarMinuteToTime(selection.startMinute)}–{calendarMinuteToTime(selection.endMinute)}
          </span>
          <button type="button" className="button secondary" onClick={clearSelection}>Mégse</button>
          <button type="button" onClick={() => setBookingDialogOpen(true)}>Foglalás</button>
        </div>
      ) : null}

      {selection && selectedRoom && bookingDialogOpen ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="selection-booking-title"
          style={{
            position: "fixed",
            inset: 0,
            zIndex: 50,
            display: "grid",
            placeItems: "center",
            padding: "1rem",
            background: "rgb(31 42 36 / 42%)",
          }}
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setBookingDialogOpen(false);
          }}
        >
          <section className="card stack" style={{ width: "min(100%, 34rem)", maxHeight: "calc(100vh - 2rem)", overflow: "auto" }}>
            <div style={{ display: "flex", alignItems: "start", justifyContent: "space-between", gap: "1rem" }}>
              <div>
                <p className="eyebrow">Kijelölt időpont</p>
                <h2 id="selection-booking-title" style={{ margin: ".15rem 0 .35rem" }}>Új foglalás</h2>
              </div>
              <button type="button" className="button secondary" onClick={() => setBookingDialogOpen(false)} aria-label="Bezárás">×</button>
            </div>

            <form action={createBooking} className="stack">
              <input type="hidden" name="idempotencyKey" value={idempotencyKey} />

              <label>Helyiség
                <select name="roomId" value={dialogRoomId || selection.roomId} onChange={(event) => setDialogRoomId(event.target.value)} required>
                  {rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}
                </select>
              </label>

              <label>Dátum
                <input name="date" type="date" defaultValue={selectedDate} required />
              </label>

              <div className="form-row">
                <label>Kezdés
                  <select name="startTime" defaultValue={calendarMinuteToTime(selection.startMinute)} required>
                    {options.slice(0, -2).map((time) => <option key={time} value={time}>{time}</option>)}
                  </select>
                </label>
                <label>Befejezés
                  <select name="endTime" defaultValue={calendarMinuteToTime(selection.endMinute)} required>
                    {options.slice(2).map((time) => <option key={time} value={time}>{time}</option>)}
                  </select>
                </label>
              </div>

              {dialogRoom?.is_training_room ? (
                <label>Használat
                  <select name="useType" defaultValue="individual">
                    <option value="individual">Egyéni</option>
                    <option value="group">Csoportos</option>
                  </select>
                </label>
              ) : (
                <input type="hidden" name="useType" value="individual" />
              )}

              <label>Megjegyzés
                <textarea name="note" maxLength={1000} rows={3} placeholder="Opcionális" />
              </label>

              <button type="submit">Foglalás mentése</button>
              <button type="button" className="button secondary" onClick={() => setBookingDialogOpen(false)}>Mégse</button>
              <p className="muted form-help">A mentéskor a backend újra ellenőrzi a jogosultságot, az előrefoglalási limitet és az ütközést.</p>
            </form>
          </section>
        </div>
      ) : null}

      {!selection ? (
        <p className="muted" style={{ margin: 0 }}>Asztali gépen húzással, mobilon hosszan nyomva jelölhetsz ki foglalási időszakot. A kijelölés 30 perces rácshoz igazodik, minimum 60 perc.</p>
      ) : null}
    </div>
  );
}
