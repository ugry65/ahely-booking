begin;

-- A pricing policy módosításának egyetlen kliensoldali belépési pontja az
-- admin_set_user_pricing_configuration wrapper. Ez kezeli együtt a policy és
-- a Fix óradíj override idővonalát, ezért a régi alacsonyabb szintű RPC nem
-- maradhat közvetlenül hívható authenticated szerepkörből.
revoke execute on function public.admin_set_user_pricing_policy(
  uuid,
  public.user_pricing_scheme,
  date,
  uuid
) from authenticated;

commit;
