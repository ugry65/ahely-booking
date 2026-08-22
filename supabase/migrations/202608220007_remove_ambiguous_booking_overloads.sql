begin;

-- The title-aware booking RPCs already keep booking_title optional via a default.
-- Separate shorter overloads make untyped SQL calls ambiguous, so remove only
-- those redundant wrappers. Legacy callers with the shorter argument lists
-- continue to resolve to the title-aware functions and receive booking_title = null.
drop function if exists public.create_booking(
  uuid, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid
);

drop function if exists public.update_booking(
  uuid, timestamptz, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid
);

drop function if exists public.update_booking_scope(
  uuid, text, timestamptz, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid
);

drop function if exists public.create_booking_series(
  uuid, uuid, timestamptz, timestamptz, public.recurrence_frequency, date, integer,
  date[], public.conflict_policy, public.booking_use_type, text, uuid
);

commit;
