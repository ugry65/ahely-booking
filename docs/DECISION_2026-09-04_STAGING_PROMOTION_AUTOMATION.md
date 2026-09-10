# Döntés: staging promóció automatizálása

Dátum: 2026-09-04  
Státusz: elfogadott staging-infrastruktúra döntés

## Probléma

A staging adatbázis dry-run és deploy GitHub Actions felületről történő kézi indítása folyamatos felhasználói jelenlétet igényelt. Ez felesleges operációs teher, miközben a main merge és a production deploy továbbra is külön, kifejezett jóváhagyáshoz kötött.

## Döntés

A repository dedikált `staging` branche a stagingre jóváhagyott, pontos commit mutatója. A branch frissítése automatikusan elindítja a `Staging database deploy` workflow-t. A folyamat sorrendje:

1. migration history ellenőrzése;
2. kötelező remote dry-run;
3. csak sikeres dry-run után staging deploy;
4. migration history és nulla függő migráció utóellenőrzése.

A promóció force push nélkül, egy pontos commit SHA-ra történik. A promóció előfeltétele az adott forrásállapot zöld Application CI és Database CI eredménye, az elvárt dry-run és a projektgazda kifejezett staging-jóváhagyása. A workflow concurrency kontrollja egyszerre legfeljebb egy staging adatbázis-deployt enged.

## Biztonsági határ

- A `SUPABASE_STAGING_DB_URL` kizárólag a GitHub `staging` Environment secretje.
- Pull request workflow nem kap staging adatbázis-hozzáférést; az adatbázis-migrációkat lokális, izolált Supabase CI ellenőrzi.
- Kézi `deploy` tartalékfuttatás csak a `staging` branchről engedélyezett.
- A staging workflow seed adatot nem tölt.
- Sikertelen deploy esetén nincs automatikus újrapróbálás vagy visszagörgetés. A futás megáll, az Actions napló megőrzi a commitot és a hibát, a következő művelet pedig külön diagnózis és jóváhagyás után történhet.

## GitHub hardening

A repository-beállításokban:

- a `staging` Environment deployment branch szabálya csak a `staging` branchet engedje;
- a `staging` branch protection tiltsa a force push-t és korlátozza a közvetlen írást;
- a workflow-fájl módosítása PR-review és zöld CI nélkül ne legyen promótálható.

Ezek a GitHub oldali hozzáférési szabályok kiegészítik, de nem helyettesítik a workflow forráskódban lévő branch-ellenőrzést.

## Production

Ez a döntés kizárólag stagingre vonatkozik. Nem engedélyez main merge-et, production adatbázis-deployt vagy production web deployt. A production folyamat továbbra is kézi, külön secrettel, backup/restore kapuval és kifejezett projektgazdai jóváhagyással.
