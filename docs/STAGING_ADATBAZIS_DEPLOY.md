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

Ezt a GitHub `staging` Environment secretjeként kell beállítani, nem általános repository secretként. Az értékhez a Supabase Dashboard **Connect** párbeszédablakából a PostgreSQL URI használható. GitHub-hosted runnerhez az IPv4-kompatibilis **Session pooler** connection string javasolt.

A URI-ban szereplő adatbázis-jelszó nem kerülhet issue-ba, PR-ba, repository-fájlba vagy chatbe. Ha a jelszó URL-speciális karaktert tartalmaz, a connection stringnek percent-encoded formátumúnak kell lennie.

## Workflow

`.github/workflows/staging-database-deploy.yml`

A kanonikus telepítési út a dedikált `staging` branch frissítése. A branchre kerülő minden új commit automatikusan:

1. ellenőrzi a migrációs státuszt;
2. `supabase db push --dry-run` előnézetet futtat;
3. sikeres előnézet után alkalmazza a függő migrációkat;
4. újra ellenőrzi a migrációs listát és egy második dry-runnal igazolja, hogy nem maradt függő migráció.

A `workflow_dispatch` megmarad diagnosztikai és helyreállítási tartalékként:

1. `dry-run` — bármely kiválasztott, megbízható ref migrációs státuszát ellenőrzi, de nem módosít adatbázist;
2. `deploy` — csak a `staging` branchről engedélyezett, és ugyanazt a dry-run → deploy → utóellenőrzés folyamatot hajtja végre.

## Promóciós kapu

A `staging` branch nem fejlesztési ág. Csak egy pontos, már review-zott commitra vihető előre, force push nélkül, ha:

- az adott commit Application CI és Database CI ellenőrzése zöld;
- a staging dry-run nem jelez váratlan migrációt vagy ütközést;
- a projektgazda a staging telepítést kifejezetten jóváhagyta;
- a promóció commit SHA-ja rögzített és visszakereshető.

A GitHub `staging` Environment deployment-branch szabálya kizárólag a `staging` branchet engedje, a branch protection pedig tiltsa a force push-t és a jogosulatlan közvetlen frissítést. A környezethez nem szükséges minden futásnál kézi reviewer-kapu, mert az explicit jóváhagyást a kontrollált branch-promóció rögzíti.

Seed adatot a workflow nem telepít automatikusan.

## Első automatikus promóció – 2026-09-04

A `staging` branch első promóciója a jóváhagyott e-mail fejlesztési forrásállapotot telepítette. A workflow #14 a kötelező dry-run után alkalmazta a cutoff-guard és a három booking-email migrációt, majd local/remote migration history egyezést és nulla függő migrációt igazolt. A következő, evidence-lépést hozzáadó fast-forward workflow #15 futása no-opként szintén PASS lett.

A promóció előtt az exact commit Application checks #588, Database tests #537 és Vercel ellenőrzése PASS volt. A közvetlen Supabase read-only ellenőrzés igazolta az új táblák jelenlétét, üres kezdeti állapotát, a közvetlen `authenticated` tábla-hozzáférés hiányát és a szükséges service-role worker jogokat. Seed, scheduler, runtime secret vagy e-mail-küldés nem történt.

## Első staging bootstrap

A staging projekt első három migrációja az UAT-környezet létrehozásakor már alkalmazásra került. A remote migration history verziói a repository eredeti fájlverzióihoz lettek igazítva:

- `202608160001_initial_core.sql`
- `202608160002_auth_profiles_rls.sql`
- `202608170001_create_booking_rpc.sql`

A workflow első `dry-run` futásának ezért kizárólag a repository fennmaradó migrációit szabad függőként mutatnia.

## Kötelező ellenőrzés deploy után

- local/remote migration history teljes egyezése;
- a deploy utáni `supabase db push --dry-run` nem mutat függő migrációt;
- Supabase Security Advisor ellenőrzés;
- kritikus RLS/RPC sémák jelenléte;
- csak ezután hozhatók létre staging UAT felhasználók és tesztadatok.

## Production

Ez a workflow production adatbázist nem ismer és nem kezel. A `staging` branch frissítése semmilyen `main` merge-et vagy production telepítést nem indít. Production deployment külön, kézi workflow-val, külön secrettel és külön kifejezett jóváhagyási kapuval történhet, csak a funkcionális UAT és a backup/restore gate teljesülése után.
