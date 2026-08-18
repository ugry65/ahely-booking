import { describe, expect, it } from "vitest";
import { parseGroupForm, parsePair, parseRoomForm, validatePermission, validUuid } from "./room-access-form";

describe("room access admin forms", () => {
  it("elfogadja a seedelt UUID-ket és elutasítja a hibás azonosítót", () => {
    expect(validUuid("11000000-0000-0000-0000-000000000001")).toBe(true);
    expect(validUuid("nem-uuid")).toBe(false);
  });
  it("normalizálja a helyiségadatokat", () => {
    expect(parseRoomForm({ roomId: "", name: " Új szoba ", displayOrder: "12" }))
      .toEqual({ ok: true, value: { roomId: null, name: "Új szoba", displayOrder: 12 } });
    expect(parseRoomForm({ roomId: "hibás", name: "Szoba", displayOrder: "-1" }).ok).toBe(false);
  });
  it("normalizálja a csoportadatokat és ellenőrzi az ID-párt", () => {
    expect(parseGroupForm({ groupId: "", name: " Terapeuták " }))
      .toEqual({ ok: true, value: { groupId: null, name: "Terapeuták" } });
    expect(parsePair("00000000-0000-0000-0000-000000000001", "11000000-0000-0000-0000-000000000001").ok).toBe(true);
    expect(parsePair("hibás", "11000000-0000-0000-0000-000000000001").ok).toBe(false);
  });
  it("can_repeat jogot csak can_book mellett enged", () => {
    expect(validatePermission(false, true)).toEqual({ ok: false, error: "Ismétlődő foglalási jog csak foglalási jog mellett adható." });
    expect(validatePermission(true, true)).toEqual({ ok: true, value: { canBook: true, canRepeat: true } });
  });
});
