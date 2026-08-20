import { describe, expect, it } from "vitest";
import { calendarMinuteToTime, normalizeCalendarSelection, snapCalendarMinute } from "./calendar-selection";

describe("calendar selection", () => {
  it("30 perces rácsra lefelé kerekít", () => {
    expect(snapCalendarMinute(9 * 60 + 17)).toBe(9 * 60);
    expect(snapCalendarMinute(9 * 60 + 44)).toBe(9 * 60 + 30);
  });

  it("egy kattintásból minimum 60 perces kijelölést készít", () => {
    expect(normalizeCalendarSelection("room-1", 9 * 60, 9 * 60)).toEqual({ roomId: "room-1", startMinute: 540, endMinute: 600 });
  });

  it("felfelé és lefelé húzásnál is rendezett időtartamot ad", () => {
    expect(normalizeCalendarSelection("room-1", 11 * 60, 9 * 60 + 30)).toEqual({ roomId: "room-1", startMinute: 570, endMinute: 690 });
  });

  it("22:00 után nem engedi a kijelölést", () => {
    expect(normalizeCalendarSelection("room-1", 21 * 60 + 30, 22 * 60 + 15)).toEqual({ roomId: "room-1", startMinute: 1260, endMinute: 1320 });
  });

  it("HH:MM formátumot ad a rejtett formmezőkhöz", () => {
    expect(calendarMinuteToTime(570)).toBe("09:30");
  });
});
