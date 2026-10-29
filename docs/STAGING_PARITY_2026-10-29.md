# Staging parity reconciliation proposal – 2026-10-29

Read-only audit: deployed main 45e765a and production caf98c8 share tree
ceda4601454bf76f5ea73328756be4ead3676a20. All 10 app_settings match.
Public schema inventory: staging1064, production1061 objects;1036 exact matches.
The 21 shared function definition differences normalize to formatting/comments,
optional AS aliases and one unused v_closed_at declaration. This is a textual
comparison, not an exhaustive semantic proof.

Staging retains 5 active bookings with historical group_hourly_rate_huf values,
none with a booking override. Their id/rate aggregate MD5 is
ca0ac0264af4283e2ee26dbdddab221f. The nullable column has no default.
The legacy BEFORE INSERT/UPDATE trigger nevertheless fills new group bookings
with5000, while production has no such trigger or column. The existing resolver
preserves historical non-null rates and otherwise follows current pricing.

Proposal: remove ONLY bookings_training_group_rate_default. Keep every column,
row, constraint, function, ACL and historical rate unchanged. No backfill,
history repair, DROP COLUMN, CASCADE, or production write. Remaining legacy
schema is intentional history compatibility, not literal schema parity.
The old admin rate RPC remains for compatibility; do not claim all RPC surfaces
are identical. Two production-only historical import RPCs also remain separate.

Regression runs the exact proposed SQL on disposable PostgreSQL17, checks
unchanged historical rows and explicit/default rates, absence of new automatic
5000 rates on insert and update, unrelated-trigger preservation, idempotence,
and the production-shaped branch without a legacy column.

Before hosted apply: green CI plus independent review (AGENTS.md critical
business logic rule), generate a forward migration with Supabase CLI, record
staging preflight history/business row hashes, then apply only that migration.
After apply: repeat hashes, verify target trigger absent and resolver/ACL
unchanged, inspect an isolated rollback test of new group pricing. Do not replay
the historical staging cleanup migrations. Production remains unchanged.

Auth audit: recovery link construction now matches, wording differs; email
requirements and86400-second link expiry match. Booking email mode is capture
on staging and disabled on production. Domain and database targets correctly
differ. No password or secret values are included in this report.

This PR is a reviewable proposal, not an applied database change. Local Supabase
CLI installation was blocked by network approval; no migration version was
invented. Hosted apply and full pricing regression are still pending.
