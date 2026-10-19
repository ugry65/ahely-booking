# Independent review – partial cancellation

Reviewer: existing read-only `booking_payment_review` agent, required by AGENTS.md.
Verdict: APPROVE, bound to exact candidate
`f652c6a0dea98529972d2d3691dfaa7d1f2beb55` (15 changed files).
Migration SHA256:
`1eac36adf985a9fa860abffa9f58391c3981dad090e11ffbe2b7cd331c7beef8`.

The reviewer found a blocking deadlock risk involving a legacy series cancellation
locking the root before a child while the partial cancellation held ledger FK
locks. Final code obtains root/selected NO KEY UPDATE NOWAIT before ledger insert;
busy rows cause an atomic, retryable P0001 instead. Real chronological series
cancellation with child UUID sorting before root is covered by concurrency CI.

Reviewed: ownership/cutoff/closure, optimistic version and idempotency, flat lineage,
immutable owner/month, preserved override/legacy rate, no physical deletion,
group receipts/context/history, once-only export and monthly money, cancellation
stats, root cancellation and later receipts, series scope guard, UI baseline.
Targeted reviewer Vitest: 18 assertions PASS; bash syntax PASS.
Full CI results (316 Vitest, 886 pgTAP plus concurrency) verified by primary agent.

Reviewer separately APPROVED the staging-only synthetic rollback smoke SQL:
new fixture identities/room/bookings, owner RPC, NULL-safe strict assertions,
two remaining fragments/five hours, unchanged receipt and single-counted export,
monthly balance, explicit ROLLBACK. Primary agent executed it successfully.
No real customer record changes or production authorization were included.

Security advisor additions are the intentionally inaccessible RLS ledger (+1 INFO)
and the guarded authenticated RPC (+1 WARN), not anonymous access grants.
Known limits: fragmented series bulk edit blocked; individual parts editable;
partial cancellation creates its own audit/outbox event but does not enable emails.
Manual authenticated browser acceptance remains for the project owner.
