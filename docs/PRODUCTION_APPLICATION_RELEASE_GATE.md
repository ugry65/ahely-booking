# Production alkalmazás-release kapu – technikai terv

**Dátum:** 2026-09-27  
**Issue:** #241  
**Állapot:** előkészítés; production konfigurációt ez a változtatás nem módosít.

## Célfolyamat

`feature branch → PR/CI → main → automatikus staging → staging UAT → explicit production jóváhagyás → production deploy`

A production alkalmazás nem kerülhet automatikusan élesbe pusztán attól, hogy egy commit bekerül a `main` ágba.

## Biztonsági alapelv

A production Vercel projektben a Production környezet Branch Tracking értékét a jelenlegi `main` ágról külön `production` release ágra kell átállítani. A GitHub kapcsolat megtartható; a staging projekt továbbra is `main`-t követ. Ezt **nem** szabad a közös `vercel.json` `git.deploymentEnabled` mezőjével megoldani, mert ugyanazt a fájlt a staging projekt is használja.

A jelenlegi éles deployment addig változatlan marad, amíg a projektgazda külön nem hagyja jóvá a production Vercel beállítás módosítását.

## Javasolt release-kapu

1. PR CI legyen zöld.
2. Merge `main`-be.
3. Staging Vercel automatikusan deployolja a `main` commitot.
4. Staging UAT/smoke PASS.
5. Production release workflow kizárólag kézi `workflow_dispatch` indítással fusson, és kizárólag egy már `main`-ben lévő, stagingen ellenőrzött teljes commit SHA-t engedjen release-jelöltként.
6. A workflow pontos megerősítő szöveget kérjen: `DEPLOY-PRODUCTION`.
7. A workflow `environment: production` alatt fusson.
8. Release előtt ellenőrizze:
   - a megadott SHA létezik és a `main` történetének része;
   - a production Vercel project ID pontosan `prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo`;
   - a production Supabase project ref pontosan `yasrmxwjojepessivhmc`;
   - a production site URL pontosan `https://foglalas.a-hely.com`;
   - a szükséges production secret-ek rendelkezésre állnak.
9. Aktiválás után a workflow kizárólag fast-forward jelleggel mozgathassa a `production` release branchet a jóváhagyott `main` SHA-ra; tetszőleges feature/preview commit közvetlen production kiadása tilos.
10. A deployolt commit SHA és Vercel deployment ID/URL auditálhatóan jelenjen meg a workflow summaryban/release evidence-ben.
11. Deploy után célzott production smoke: canonical URL + `/api/health`.
12. Hiba esetén a korábbi ismert jó deploymentre történő rollback legyen dokumentált és kézi jóváhagyású.

## Production Vercel projekt átállítása

Csak a fenti workflow staging/száraz ellenőrzése után, külön projektgazdai jóváhagyással:

- GitHub `production` release branch létrehozása az aktuális, ismert jó production baseline SHA-ról;
- a `production` branch közvetlen, véletlen módosítása elleni GitHub-védelem beállítása;
- production Vercel Production Branch Tracking átállítása `main` → `production`;
- a Git kapcsolat megmarad, staging Git kapcsolat változatlan marad;
- ellenőrizni kell, hogy a jelenlegi production deployment és custom domain továbbra is kiszolgál;
- egy kontrollált `main` commit után igazolni kell: staging deploy történik, production automatikus deploy NEM történik;
- ezt követően egy kontrollált release-promócióval igazolni kell, hogy kizárólag a `production` branch előreléptetése indít production deploymentet;
- csak ezután tekinthető a release-isoláció lezártnak.

## GitHub production environment

A workflow `environment: production` használata önmagában nem bizonyít emberi approvalt. A GitHub repository Settings → Environments → production alatt külön ellenőrizni kell a Required reviewers / deployment protection beállítást. Ennek hiányában a workflow saját exact-confirmation guardja kötelező, de a reviewer-védelem továbbra is javasolt.

## Secret-scope

A production Vercel/Supabase secret-ek kizárólag a production release környezethez legyenek elérhetők. Preview/staging scope-ba production service-role vagy production DB URL nem kerülhet.

## Nem része ennek a változtatásnak

- production DB migráció;
- production Supabase/Auth módosítás;
- production domain módosítás;
- production Git kapcsolat tényleges letiltása;
- automatikus production deployment.

Ezek csak külön jóváhagyott aktiválási lépésben történhetnek.

## Visszaállítás az átállás közben

Ha a `main` → `production` Branch Tracking átállítás után a release útvonal nem működik megfelelően, **nem kell az alkalmazást vagy az adatbázist visszaállítani**: a már futó production deployment változatlanul kiszolgál. A konfigurációs rollback a Vercel Production Branch Tracking visszaállítása `main` értékre. Ezt is csak projektgazdai jóváhagyással szabad elvégezni.

## Megfigyelt jelenlegi állapot – 2026-09-27

- production Vercel Production Branch Tracking: `main`;
- production Git repository kapcsolat: `ugry65/ahely-booking`;
- production Deploy Hook: nincs;
- GitHub `production` branch: jelenleg nem létezik;
- repository ruleset: jelenleg nincs;
- production Cron Jobs globálisan **Enabled**; ezt a release-isoláció részeként nem módosítjuk.

## Baseline egyezőség – 2026-09-27

Read-only ellenőrzés alapján a jelenleg futó production deployment Git SHA-ja és a GitHub `main` HEAD azonos:

- production deployment SHA: `5a34742d2297bd3b6ac66a73ca932ee7136e2ad5`;
- GitHub `main` HEAD: `5a34742d2297bd3b6ac66a73ca932ee7136e2ad5`.

Ez legyen a kezdeti `production` release branch létrehozási pontja. A branch létrehozása előtt újra ellenőrizni kell, hogy a production deployment nem változott.

GitHub ellenőrzés szerint a `main` jelenleg `protected: false`, repository ruleset nincs. A release-isoláció részeként legalább a `production` branch közvetlen véletlen módosítását meg kell akadályozni; a `main` védelmét külön repository-governance hardeningként szintén be kell vezetni úgy, hogy a meglévő PR/CI folyamatot ne törje el.


## Független review utáni kötelező kapuk – 2026-09-28

A production Branch Tracking átállítása **NO-GO**, amíg az alábbiak nincsenek igazolva:

1. `main` branch protection/ruleset: PR kötelező, szükséges CI checkek kötelezők, force-push és törlés tiltott.
2. GitHub production environment: Required reviewers ténylegesen aktív, deployment branch/tag policy explicit és ellenőrzött; feature ágról módosított workflow nem férhet hozzá production secretekhez.
3. Production Vercel Preview/Development env scope audit: production Supabase/service-role/DB/SMTP/cron secret nem lehet preview scope-ban.
4. Vercel team role/token audit: production promote/redeploy megkerülési út minimalizálva.
5. Production DB deploy workflow release SHA-hoz kötése; DB és app release nem csúszhat eltérő commitokra.
6. Staging evidence: a release SHA staging deploymentje READY és az UAT jóváhagyás SHA-hoz kötött.
7. Production identity guard ne csak kézi címkéket hasonlítson: a tényleges URL/kulcs/projekt összerendelést is ellenőrizze, ahol biztonságosan lehetséges.
8. Rehearsal production secret nélkül igazolja a branch tracking, branch-push→Vercel deployment és rollback viselkedést.
9. Átállási ablakban main freeze és deployment-queue ellenőrzés.
10. A `production` branch csak fast-forward release-t engedjen; force push normál release-ben tilos.

### Cron-konfigurációs eltérés

Repo-ellenőrzés szerint a `vercel.json` négy `/api/internal/production-health` cront ütemez, miközben a `main` fában ilyen Next.js route nincs. A dokumentált és létező publikus health kontraktus a `/api/health`. Emiatt a #240 jelenlegi változata nem tekinthető véglegesnek: a booking-email-worker cron eltávolítása mellett a hibás/felesleges production-health cronokat külön döntéssel rendezni kell. Production Cron Jobs globális kapcsolóját ettől függetlenül nem kapcsoljuk ki ellenőrizetlenül.
