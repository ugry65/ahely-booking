const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

export type PermissionForm = {
  firstId: string;
  secondId: string;
  canBook: boolean;
  canRepeat: boolean;
};

export function validUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
}

export function parseRoomForm(input: Record<string, string>) {
  const roomId = input.roomId?.trim() || null;
  const name = input.name?.trim() ?? "";
  const displayOrder = Number(input.displayOrder);
  if ((roomId !== null && !validUuid(roomId)) || !name || name.length > 120 ||
      !/^\d+$/.test(input.displayOrder ?? "") || !Number.isSafeInteger(displayOrder)) {
    return { ok: false as const, error: "A helyiség adatai hiányosak vagy érvénytelenek." };
  }
  return { ok: true as const, value: { roomId, name, displayOrder } };
}

export function parseGroupForm(input: Record<string, string>) {
  const groupId = input.groupId?.trim() || null;
  const name = input.name?.trim() ?? "";
  if ((groupId !== null && !validUuid(groupId)) || !name || name.length > 120) {
    return { ok: false as const, error: "A csoport adatai hiányosak vagy érvénytelenek." };
  }
  return { ok: true as const, value: { groupId, name } };
}

export function parsePair(firstId: string, secondId: string) {
  if (!validUuid(firstId) || !validUuid(secondId)) {
    return { ok: false as const, error: "Érvénytelen felhasználó-, csoport- vagy helyiségazonosító." };
  }
  return { ok: true as const, value: { firstId, secondId } };
}

export function validatePermission(canBook: boolean, canRepeat: boolean) {
  if (canRepeat && !canBook) {
    return { ok: false as const, error: "Ismétlődő foglalási jog csak foglalási jog mellett adható." };
  }
  return { ok: true as const, value: { canBook, canRepeat } };
}
