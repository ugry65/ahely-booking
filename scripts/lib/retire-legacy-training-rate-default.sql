-- Forward-only reconciliation: preserve historical rates and the resolver.
-- Apply through a versioned migration after independent review.
begin;
drop trigger if exists bookings_training_group_rate_default on public.bookings;
commit;
