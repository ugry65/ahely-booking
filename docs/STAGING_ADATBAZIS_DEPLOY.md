# Staging adatbázis deploy

## Cél

A `ahely-booking-staging` Supabase projekt sémája kizárólag a GitHub repository `supabase/migrations` könyvtárából épüljön fel. Remote séma- vagy jogosultságmódosítást a Supabase Dashboard SQL/Table Editorában nem végzünk.

## Staging projekt

- Supabase project: `ahely-booking-staging`
- project ref: `fvwapntzhavhgazeflri`
- régió: `eu-west-2`
- cél: kizárólag fejlesztési/UAT környezet, production adat nélkül

## GitHub secret

A workflow egyetlen érzékeny értéket használ:

- `SUPABASE_STAGING_DB_URL`

Ezt GitHub Environment (`staging`) vagy repository secretként kell beállítani. Az értékhez a Supabase Dashboard **Connect** párbeszédablakából a PostgreSQL URI használható. GitHub-hosted runnerhez az IPv4-kompatibilis **Session pooler** connection string javasolt.

A URI-ban szereplő adatbázis-jelszó nem kerülhet issue-ba, PR-ba, repository-fájlba vagy chatbe. Ha a jelszó URL-speciális karaktert tartalmaz, a connection stringnek percent-encoded formátumúnak kell lennie.

## Workflow

`.github/workflows/staging-database-deploy.yml`

A workflow kizárólag kézzel (`workflow_dispatch`) indítható, és két módja van:

1. `dry-run` — migrációs státusz + `supabase db push --dry-run`; nem módosítja a staging sémát.
2. `deploy` — ugyanazt a dry-runt lefuttatja, majd explicit választás esetén alkalmazza a függő migrációkat.

Seed adatot a workflow nem telepít automatikusan.

## Első staging bootstrap

A staging projekt első három migrációja az UAT-környezet létrehozásakor már alkalmazásra került. A remote migration history verziói a repository eredeti fájlverzióihoz lettek igazítva:

- `202608160001_initial_core.sql`
- `202608160002_auth_profiles_rls.sql`
- `202608170001_create_booking_rpc.sql`

A workflow első `dry-run` futásának ezért kizárólag a repository fennmaradó migrációit szabad függőként mutatnia.

## Kötelező ellenőrzés deploy után

- local/remote migration history teljes egyezése;
- Supabase Security Advisor ellenőrzés;
- kritikus RLS/RPC sémák jelenléte;
- csak ezután hozhatók létre staging UAT felhasználók és tesztadatok.

## Production

Ez a workflow production adatbázist nem ismer és nem kezel. Production deployment külön workflow, külön secret és külön jóváhagyási kapu lesz, csak a funkcionális UAT és a backup/restore gate teljesülése után.
