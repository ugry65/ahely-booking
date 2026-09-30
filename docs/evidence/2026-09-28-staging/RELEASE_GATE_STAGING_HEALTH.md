# #241 staging health helyreállítás — 2026-09-28

## Kiinduló állapot

- Staging Vercel projekt: `prj_LzVgZgZBCAj4zA64YoYED3XkLGKW`.
- Staging fő deployment: `dpl_8fgYFyfGJBR75yuu6VqxBcS9ne9p`, Git SHA `5a34742d2297bd3b6ac66a73ca932ee7136e2ad5`, READY.
- `https://ahely-booking-staging-web.vercel.app/api/health`: kétszer HTTP 503, `database: error`.
- Staging Supabase `fvwapntzhavhgazeflri`: ACTIVE_HEALTHY; a `public.system_health_check()` függvény és a `20260917100000` migráció hiányzott. Productionben a függvény létezett; productiont nem módosítottuk.

## Staging helyreállítás

A repository meglévő `supabase/migrations/20260917100000_system_health_check.sql` fájljának függvény-, revoke-, grant- és comment SQL-jét alkalmaztuk kizárólag stagingen. A Supabase távoli migration history ezt `20260928091003_system_health_check_from_20260917100000` néven rögzítette. A repository eredeti fájlját nem módosítottuk. A két verzió eltérését a későbbi staging migration reconciliationnél figyelembe kell venni; az összes függő migrációt vakon futtatni tilos.

## Utóellenőrzés

- `public.system_health_check()` → `true`.
- `anon` EXECUTE → `true`; `PUBLIC` EXECUTE → `false`.
- Staging `/api/health` → HTTP 200, `ok: true`, `database: ok`.
- Üzleti adatot, Authot és production konfigurációt nem módosítottunk.

Ez a health smoke nem helyettesíti a release SHA-hoz kötött staging UAT-ot vagy a production release workflow száraz futását. A #242 PR branch preview deploymentje sem azonos a staging projekt `main` deploymentjével.
