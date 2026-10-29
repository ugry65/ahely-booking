# Staging parity reconciliation proposal – 2026-10-29

Read-only audit: deployed main 45e765a and production caf98c8 share tree
ceda4601454bf76f5ea73328756be4ead3676a20. All 10 app_settings match.
Public schema inventory: staging 1064, production 1061 objects; 1036 exact matches.
The 21 shared function definition differences normalize to formatting/comments,
optional AS aliases and one unused v_closed_at declaration. This is a textual
comparison, not an exhaustive semantic proof.

Staging retains 5 active bookings with historical group_hourly_rate_huf values,
none with a booking override. Their id/rate aggregate MD5 is
ca0ac0264af4283e2ee26dbdddab221f. The nullable column has no default.
The legacy BEFORE INSERT/UPDATE trigger nevertheless fills new group bookings
with 5000, while production has no such trigger or column. The existing resolver
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
requirements and 86400-second link expiry match. Booking email mode is capture
on staging and disabled on production. Domain and database targets correctly
differ. No password or secret values are included in this report.

This PR is a reviewable proposal, not an applied database change. Local Supabase
CLI installation was blocked by network approval; no migration version was
invented. Hosted apply and full pricing regression are still pending.


## Independent review and pre-apply follow-up

External Claude review APPROVE on exact head
531f5140f690231902728548fa01d2c6224539c6. Reviewer ran PostgreSQL16 regression,
a no-op mutation test and an original-trigger fidelity test; no blocker.
Hosted apply remains gated by the follow-up below and green full DB CI.

M-1: four retained rows share creation time 2026-09-28 15:24:59Z, service dates
September17/18/25/28 and rate5000. No per-booking audit rows survive for those
four IDs, so their exact original insertion path is not proven; they are not
reclassified or modified. The fifth was created 2026-10-28 16:06:10Z for a
November25 group booking, with matching booking.created audit. Its rate5000
is consistent with the automatic legacy default, not proof of an explicit
owner tariff decision. Existing id/rate MD5 ca0ac0264af4283e2ee26dbdddab221f
covers all five; preserve all of them. No identifiers/personal details copied.

M-2/M-3/M-4: Supabase CLI2.116.0 was found in the installed package cache and
successfully generated 20261029111608_retire_legacy_training_rate_default.sql.
Payload is transaction-scoped, lock_timeout3s, DROP TRIGGER only. The isolated
regression asserts exact helper/migration equality. Added pgTAP regression
123 exercises the actual resolver, actual monthly calculation and a real
rooms-aware legacy trigger on the DB rebuilt from the repository migrations.
No direct helper execution against hosted DB is allowed.

M-5: read-only global pricing audit found real data differences:
- from October1, first central tier staging2600 vs production2700 HUF;
  the1900/1700 tiers match;
- staging Training-room group5000 from October1; production5000 through
  October14 then6000 from October15;
- user override/policy row counts staging1/1 vs production6/0. These belong to
  distinct accounts and cannot be safely copied by UUID or count alone.
Therefore removing the trigger aligns the pricing algorithm, NOT the numeric
charges between different configured datasets. This PR does not change tariffs,
user overrides, policies or historical prices. A representative test fixture
must explicitly select its expected tariff; tariff-data synchronization is a
separate scope, never a production write.

The earlier "Local CLI installation blocked" paragraph is historical; CLI
migration generation has now completed. Full pgTAP CI result and live apply
will be recorded separately. Production remains unchanged.
