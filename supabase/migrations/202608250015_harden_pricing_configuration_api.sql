begin;

-- A user pricing policy közvetlen admin RPC-je legacy belső helperré válik.
-- A kliensoldal kizárólag az egységes admin_set_user_pricing_configuration
-- wrapperen keresztül módosíthat díjazást, mert csak az kezeli együtt
-- a pricing policy és a fix user override idővonalát.
revoke execute on function public.admin_set_user_pricing_policy(
  uuid,
  public.user_pricing_scheme,
  date,
  uuid
) from authenticated;

commit;
