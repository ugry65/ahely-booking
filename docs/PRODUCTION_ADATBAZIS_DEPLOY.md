# Production adatbázis deploy

## Cél

Az A-Hely production Supabase sémája kizárólag a GitHub repository `supabase/migrations` könyvtárából épüljön fel. Production séma- vagy jogosultságmódosítást a Supabase Dashboard SQL/Table Editorában nem végzünk.

## Production projekt

- Supabase project: `ahely-booking-production`
- project ref: `yasrmxwjojepessivhmc`
- régió: `eu-west-2` / West Europe (London)
- cél: éles foglalási és elszámolási adatbázis

## GitHub secret

A workflow egyetlen érzékeny értéket használ:

- `SUPABASE_PRODUCTION_DB_URL`

Ezt elsődlegesen GitHub Environment (`production`) secretként kell beállítani. Az értékhez a Supabase Dashboard **Connect** párbeszédablakából a PostgreSQL URI használható. GitHub-hosted runnerhez az IPv4-kompatibilis **Session pooler** connection string javasolt.

A URI-ban szereplő adatbázis-jelszó nem kerülhet issue-ba, PR-ba, repository-fájlba vagy chatbe. Ha a jelszó URL-speciális karaktert tartalmaz, a connection stringnek percent-encoded formátumúnak kell lennie.

## Workflow

`.github/workflows/production-database-deploy.yml`

A workflow kizárólag kézzel (`workflow_dispatch`) indítható, és két módja van:

1. `dry-run` — migrációs státusz + `supabase db push --dry-run`; nem módosítja a production sémát.
2. `deploy` — ugyanazt a dry-runt lefuttatja, majd csak explicit `PRODUCTION` megerősítés esetén alkalmazza a függő migrációkat.

A workflow GitHub `production` environmentet használ, így később environment protection / required reviewer is beállítható.

## 2026-08-24 production bootstrap állapot

A production projekt frissen létrehozott, üzleti adatot még nem tartalmaz. A bootstrap során az első három repository-migráció közül az alábbiak már alkalmazásra kerültek:

- `202608160001_initial_core.sql`
- `202608160002_auth_profiles_rls.sql`
- `202608170001_create_booking_rpc.sql`

Az API-val alkalmazott migrációk remote history verziói a repository eredeti fájlverzióihoz lettek igazítva, hogy a későbbi `supabase db push` ne lásson mesterséges driftet.

A további migrációkat már a production workflow kezeli. A workflow első dry-runjának kizárólag a repository még hiányzó migrációit szabad függőként mutatnia.

## Kötelező sorrend

1. repository `main` és production deployment konzisztencia ellenőrzése;
2. production DB backup/restore képesség ellenőrzése a go-live előtt;
3. workflow `dry-run`;
4. pending migrációlista review;
5. explicit production jóváhagyás;
6. workflow `deploy` + `PRODUCTION` megerősítés;
7. remote migration history ellenőrzése;
8. Supabase Security Advisor ellenőrzés;
9. kritikus RLS/RPC és booking-concurrency ellenőrzés;
10. csak ezután Vercel production környezeti változók átállítása az új production Supabase projektre.

## Fontos tiltások

- production DB-változtatás nem történhet staging secretből;
- production és staging adatbázis-URL nem lehet azonos;
- Vercel production nem állítható át az új projektre hiányos migrációk mellett;
- éles foglalási adat betöltése előtt backup/restore követelményt rendezni kell;
- production migrációt nem indítunk automatikusan `main` pushra.
