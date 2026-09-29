# Staging adatbázis deploy

## Cél

A `ahely-booking-staging` Supabase projekt aktuális sémáját a Gitben verziózott forward migrationök határozzák meg. A staging történeti migration lineage-e nem azonos minden korai repository fájlnévvel: a [2026-09-29-i reconciliation](STAGING_SCHEMA_RECONCILIATION_2026-09-29.md) a tényleges lefutást és az átmeneti UAT SQL-eket tételesen dokumentálja.

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

A workflow a staging DB-secret védelme érdekében kizárólag kézzel (`workflow_dispatch`), áttekintett branchről indítható. Két mód választható:

1. `dry-run` — a staging projektref ellenőrzése, a tényleges remote version/name/SQL-hash history összevetése a `scripts/staging-migration-history-baseline.json` manifesttel, majd a `scripts/staging-migration-projection.py` ideiglenes projekciójában `supabase db push --dry-run`. Nem módosít staging sémát vagy historyt.
2. `deploy` — ugyanaz a preflight, majd csak explicit kézi választás esetén a jóváhagyott új repository migrationök alkalmazása.

A 90 eredeti remote rekord és a később ténylegesen lefutott új migrationök valós historyja megmarad. A 45 történeti helyi verzióeltérés pontos fájlhash-sel van kizárva az ideiglenes CLI-projekcióból; nincs remote history-repair. Az alkalmazottnak tekintett remote verziók projekciós SQL-je kötelező hibával leáll, ha valaha újrafutna. A `20260927103201` adatürítő és `20260927103212` UAT-ellenőrző migration rekordjának hiánya már a dry-run előtt blokkol. A `20260914095042` nem lett utólag appliednek jelölve; a kívánt végső séma új forward migrationből állt elő.

Új deploy előtt a history manifestet a staging read-only history és a repository alapján ellenőrizni kell; a review-nak jóvá kell hagynia minden új függő SQL-t. Sikeres deploy után a manifestbe a **tényleges** új verzió/name/SQL-hash kerül, az objektumszintű post-check és DB/schema tesztek után. Ha a manifest vagy egy történeti fájl hash-e eltér, a workflow fail-closed módon áll meg; soha ne jelöljünk egy régi SQL-t appliednek csak a lista egyeztetéséért.

Seed adatot a workflow nem telepít automatikusan.

## Első staging bootstrap

A staging projekt első három migrációja az UAT-környezet létrehozásakor már alkalmazásra került. A remote migration history verziói a repository eredeti fájlverzióihoz lettek igazítva:

- `202608160001_initial_core.sql`
- `202608160002_auth_profiles_rls.sql`
- `202608170001_create_booking_rpc.sql`

A workflow első `dry-run` futásának ezért kizárólag a repository fennmaradó migrációit szabad függőként mutatnia.

## Kötelező ellenőrzés deploy után

- a manifesttel bizonyított valós remote history és kizárólag jóváhagyott új függő migration;
- Supabase Security Advisor ellenőrzés;
- kritikus RLS/RPC sémák jelenléte;
- csak ezután hozhatók létre staging UAT felhasználók és tesztadatok.

## Production

Ez a workflow production adatbázist nem ismer és nem kezel. Production deployment külön workflow, külön secret és külön jóváhagyási kapu lesz, csak a funkcionális UAT és a backup/restore gate teljesülése után.
