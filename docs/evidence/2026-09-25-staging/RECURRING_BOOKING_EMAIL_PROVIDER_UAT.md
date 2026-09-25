# Recurring booking e-mail – staging real-provider UAT evidence

Date: 2026-09-25  
Environment: dedicated staging (`fvwapntzhavhgazeflri`, `ahely-booking-staging-web`)  
Main deployment used: `dpl_3DnofN39mw7cUyqgxQjmNfgJDutR`  
Git SHA: `b16d092aec75ab4c311dd393ffeec9807e92033c`

## Purpose

Close the remaining #150 / booking-email release gate with a real-provider test of the recurring-series summary. Production was not changed.

## Controlled recipient

A user-owned staging profile was used: `olah.imre@a-hely.com`. No migrated customer address was used.

## Scenario

A weekly recurring series was created through the canonical `create_booking_series` RPC for `1.Szoba-családi`:

- first planned occurrence: 2026-10-19 09:00 Europe/Budapest;
- frequency: weekly;
- planned count: 4;
- explicit exception date: 2026-10-26;
- therefore 3 bookings were actually created;
- title: `UAT ismétlődő e-mail #150`;
- correlation id: `e1500000-0000-0000-0000-000000000001`.

The immutable outbox snapshot contained:

- `scope=series`;
- `recurrence=Hetente`;
- `affected_count=3`;
- `first_start_at=2026-10-19T07:00:00Z`;
- `last_end_at=2026-11-09T09:00:00Z`;
- `skipped_dates=[2026-10-26]`.

## Provider / worker evidence

The outbox row reached `sent` in one attempt, with no safe error code. A provider message id was stored. The Vercel scheduled worker returned HTTP 200 at the matching processing time.

## Human acceptance

The recipient confirmed in chat that the real e-mail arrived and that all required recurring-series information was present and visually correct: first occurrence, last occurrence, `Hetente` recurrence, and the skipped 2026-10-26 occurrence. Result: **PASS**.

## Cleanup

The UAT series was cancelled through the canonical `cancel_booking_scope(..., 'series', ...)` path with reason `Staging UAT lezárás`, correlation id `e1500000-0000-0000-0000-000000000002`. All three created bookings became `cancelled`, preserving auditability instead of deleting booking/audit history. The resulting controlled cancellation e-mail also reached `sent` in one attempt with no error, proving the series-cancellation provider path while staging was still in send mode.

## Remaining safety action

After provider UAT, staging `BOOKING_EMAIL_MODE` must be returned from `send` to the non-real-send/capture mode and redeployed. Production e-mail mode remains unchanged and is not approved by this evidence.
