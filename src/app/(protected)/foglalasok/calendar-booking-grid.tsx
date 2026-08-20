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

const PIXELS_PER_MINUTE = 1;
const TIMELINE_HEIGHT = (CALENDAR_CLOSE_MINUTE - CALENDAR_OPEN_MINUTE) * PIXELS_PER_MINUTE;

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

export function CalendarBookingGrid({ rooms, bookings, selectedDate }: Props) {
  const [selection, setSelection] = useState<CalendarSelection | null>(null);
  const [bookingDialogOpen, setBookingDialogOpen] = useState(false);
  const dragState = useRef<{ roomId: string; anchorMinute: number } | null>(null);
  const idempotencyKey = useMemo(
    () => crypto.randomUUID(),
    [selection?.roomId, selection?.startMinute, selection?.endMinute],
  );

  function minuteFromPointer(element: HTMLElement, clientY: number) {
    const rect = element.getBoundingClientRect();
    return CALENDAR_OPEN_MINUTE + (clientY - rect.top) / PIXELS_PER_MINUTE;
  }

  function beginSelection(roomId: string, event: PointerEvent<HTMLDivElement>) {
    if ((event.target as HTMLElement).closest(".booking-block")) return;
    event.preventDefault();
    setBookingDialogOpen(false);
    event.currentTarget.setPointerCapture(event.pointerId);
    const anchorMinute = minuteFromPointer(event.currentTarget, event.clientY);
    dragState.current = { roomId, anchorMinute };
    setSelection(normalizeCalendarSelection(roomId, anchorMinute, anchorMinute));
  }

  function moveSelection(roomId: string, event: PointerEvent<HTMLDivElement>) {
    const drag = dragState.current;
    if (!drag || drag.roomId !== roomId) return;
    setSelection(normalizeCalendarSelection(roomId, drag.anchorMinute, minuteFromPointer(event.currentTarget, event.clientY)));
  }

  function endSelection() {
    dragState.current = null;
  }

  function clearSelection() {
    setBookingDialogOpen(false);
    setSelection(null);
  }

  const selectedRoom = selection ? rooms.find((room) => room.room_id === selection.roomId) : null;

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
                <span key={index} style={{ top: `${index * 60}px` }}>{String(index + 7).padStart(2, "0")}:00</span>
              ))}
            </div>

            {rooms.map((room) => (
              <div
                className="room-timeline"
                key={room.room_id}
                style={{ height: `${TIMELINE_HEIGHT}px`, cursor: "crosshair", touchAction: "pan-x" }}
                onPointerDown={(event) => beginSelection(room.room_id, event)}
                onPointerMove={(event) => moveSelection(room.room_id, event)}
                onPointerUp={endSelection}
                onPointerCancel={endSelection}
                aria-label={`${room.room_name} szabad időpontjai. Foglaláshoz húzz egy időszakot.`}
              >
                {selection?.roomId === room.room_id ? (
                  <div
                    style={{
                      position: "absolute",
                      left: ".2rem",
                      right: ".2rem",
                      zIndex: 2,
                      top: `${selection.startMinute - CALENDAR_OPEN_MINUTE}px`,
                      height: `${selection.endMinute - selection.startMinute}px`,
                      padding: ".35rem .45rem",
                      border: "2px solid #235c43",
                      borderRadius: ".35rem",
                      background: "rgb(220 235 226 / 88%)",
                      color: "#183c2c",
                      pointerEvents: "none",
                      display: "flex",
                      flexDirection: "column",
                      fontSize: ".78rem",
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
                      style={{ top: `${start - CALENDAR_OPEN_MINUTE}px`, height: `${Math.max(end - start, 30)}px` }}
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
        <div
          aria-live="polite"
          style={{
            position: "fixed",
            right: "6.5rem",
            bottom: "2rem",
            zIndex: 39,
            display: "flex",
            alignItems: "center",
            gap: ".5rem",
            padding: ".45rem",
            border: "1px solid #a8cbb5",
            borderRadius: ".8rem",
            background: "#edf8f0",
            boxShadow: "0 .4rem 1rem rgb(31 42 36 / 18%)",
          }}
        >
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
                <p className="muted" style={{ margin: 0 }}>
                  {selectedRoom.room_name} · {selectedDate} · {calendarMinuteToTime(selection.startMinute)}–{calendarMinuteToTime(selection.endMinute)}
                </p>
              </div>
              <button type="button" className="button secondary" onClick={() => setBookingDialogOpen(false)} aria-label="Bezárás">×</button>
            </div>

            <form action={createBooking} className="stack">
              <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
              <input type="hidden" name="roomId" value={selection.roomId} />
              <input type="hidden" name="date" value={selectedDate} />
              <input type="hidden" name="startTime" value={calendarMinuteToTime(selection.startMinute)} />
              <input type="hidden" name="endTime" value={calendarMinuteToTime(selection.endMinute)} />
              {selectedRoom.is_training_room ? (
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
              <p className="muted form-help">A mentéskor a backend újra ellenőrzi a jogosultságot, az előrefoglalási limitet és az ütközést.</p>
            </form>
          </section>
        </div>
      ) : null}

      {!selection ? (
        <p className="muted" style={{ margin: 0 }}>Foglaláshoz kattints és húzz egy szabad idősávon. A kijelölés 30 perces rácshoz igazodik, minimum 60 perc.</p>
      ) : null}
    </div>
  );
}
