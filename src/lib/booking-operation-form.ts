import { parseBookingForm, type BookingRequest } from "./booking-form";

const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

export type UpdateBookingRequest = BookingRequest & { bookingId: string; expectedUpdatedAt: string };
export type OperationResult<T> = { ok: true; value: T } | { ok: false; error: string };

export function parseUpdateBookingForm(input: Record<string, string>): OperationResult<UpdateBookingRequest> {
  const bookingId = input.bookingId?.trim() ?? "";
  const expectedUpdatedAt = input.expectedUpdatedAt?.trim() ?? "";
  if (!UUID_PATTERN.test(bookingId) || !expectedUpdatedAt || Number.isNaN(Date.parse(expectedUpdatedAt)))
    return { ok: false, error: "A módosítási adatok hiányosak vagy érvénytelenek." };
  const booking = parseBookingForm(input);
  if (!booking.ok) return { ok: false, error: booking.error };
  return { ok: true, value: { ...booking.value, bookingId, expectedUpdatedAt } };
}

export function parseCancelBookingForm(input: Record<string, string>): OperationResult<{ bookingId: string; reason: string | null; idempotencyKey: string }> {
  const bookingId = input.bookingId?.trim() ?? "";
  const idempotencyKey = input.idempotencyKey?.trim() ?? "";
  const reason = input.reason?.trim() ?? "";
  if (!UUID_PATTERN.test(bookingId) || !UUID_PATTERN.test(idempotencyKey))
    return { ok: false, error: "A lemondási adatok hiányosak vagy érvénytelenek." };
  if (reason.length > 500) return { ok: false, error: "A lemondás indoka legfeljebb 500 karakteres lehet." };
  return { ok: true, value: { bookingId, reason: reason || null, idempotencyKey } };
}
