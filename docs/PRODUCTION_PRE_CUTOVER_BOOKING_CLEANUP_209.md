# Production pre-cutover booking cleanup (#209)

This runbook is intentionally fail-closed and applies only to the owner-approved removal of the historical Papp Dalma AllBooked production migration-test residue.

## Required preconditions

- Latest isolated production restore drill is green.
- Production contains exactly 21 bookings.
- All 21 are voided and belong to the same Papp Dalma profile.
- Exactly 21 corresponding rows exist in allbooked_migration_bookings.
- Historical audit evidence contains the expected 21 import and 21 test-void events.
- There are no booking cancellation, operation, recurrence, settlement-line, settlement, payment, or outbox dependencies.
- Any mismatch aborts the cleanup.

## Execution design

The cleanup runs as one database transaction. The two physical-delete guards may only be suspended inside that transaction and must be restored before commit. The migration ledger rows are removed first, then the 21 voided test bookings. Historical audit rows are never deleted. A new cleanup audit event records the approved pre-cutover removal.

If any assertion or trigger restoration fails, the whole transaction rolls back.

## Postconditions

- bookings = 0
- allbooked_migration_bookings = 0
- historical 21+21 audit evidence remains
- one cleanup audit event exists
- settlement/payment/outbox counts remain zero
- both deletion guards are active
- no production migration/schema deployment is implied or authorized by this cleanup
