export const CALENDAR_OPEN_MINUTE = 7 * 60;
export const CALENDAR_CLOSE_MINUTE = 22 * 60;
export const CALENDAR_SLOT_MINUTES = 30;
export const CALENDAR_MIN_BOOKING_MINUTES = 60;

export type CalendarSelection = {
  roomId: string;
  startMinute: number;
  endMinute: number;
};

export function snapCalendarMinute(rawMinute: number) {
  const snapped = CALENDAR_OPEN_MINUTE + Math.floor((rawMinute - CALENDAR_OPEN_MINUTE) / CALENDAR_SLOT_MINUTES) * CALENDAR_SLOT_MINUTES;
  return Math.min(CALENDAR_CLOSE_MINUTE - CALENDAR_SLOT_MINUTES, Math.max(CALENDAR_OPEN_MINUTE, snapped));
}

export function normalizeCalendarSelection(roomId: string, anchorMinute: number, currentMinute: number): CalendarSelection {
  const anchor = snapCalendarMinute(anchorMinute);
  const current = snapCalendarMinute(currentMinute);
  let startMinute = Math.min(anchor, current);
  let endMinute = Math.max(anchor, current) + CALENDAR_SLOT_MINUTES;

  if (endMinute - startMinute < CALENDAR_MIN_BOOKING_MINUTES) {
    if (startMinute + CALENDAR_MIN_BOOKING_MINUTES <= CALENDAR_CLOSE_MINUTE) {
      endMinute = startMinute + CALENDAR_MIN_BOOKING_MINUTES;
    } else {
      startMinute = CALENDAR_CLOSE_MINUTE - CALENDAR_MIN_BOOKING_MINUTES;
      endMinute = CALENDAR_CLOSE_MINUTE;
    }
  }

  return { roomId, startMinute, endMinute };
}

export function calendarMinuteToTime(minute: number) {
  return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
}
