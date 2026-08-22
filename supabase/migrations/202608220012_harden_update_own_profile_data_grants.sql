begin;

-- Self-service profile updates are authenticated-only. PostgreSQL grants EXECUTE
-- on new functions to PUBLIC by default unless it is explicitly revoked.
revoke all on function public.update_own_profile_data(text,text,text,text,text,text,text,text,uuid) from public, anon;
grant execute on function public.update_own_profile_data(text,text,text,text,text,text,text,text,uuid) to authenticated, service_role;

commit;
