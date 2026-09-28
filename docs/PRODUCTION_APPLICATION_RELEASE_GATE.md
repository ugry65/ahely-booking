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
7. A workflow a ténylegesen létrehozott `Production – ahely-booking` GitHub Environment alatt fusson, kizárólag `main` dispatch esetén, `ugry65` actorral.
8. Release előtt ellenőrizze:
   - a megadott SHA a `main` aktuális HEAD-je, így későbbi merge nem kerülheti meg a staging UAT-ot;
   - a production Vercel project ID pontosan `prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo`;
   - a production Supabase project ref pontosan `yasrmxwjojepessivhmc`;
   - a production site URL pontosan `https://foglalas.a-hely.com`;
   - a szükséges production secret-ek rendelkezésre állnak;
   - a staging Vercel projektben valóban létezik READY, `main` ágból készült production-target deployment a pontos SHA-val;
   - a SHA-hoz kötött staging UAT-jegyzőkönyv hivatkozása rögzített.
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

A workflow `Production – ahely-booking` environment használata önmagában nem bizonyít emberi approvalt. A 2026-09-28-i read-only UI-ellenőrzés szerint a Required reviewers kapcsoló elérhető, de **ki van kapcsolva**; az admin bypass be van kapcsolva. Az environment kizárólag a `main` ágat engedi deployment branchként, és jelenleg nincs benne secret vagy variable. Az environment név szerint különbözik a régi `Production` environmenttől, amelynek saját secretjei és változói vannak; ezek nem öröklődnek át. A kézi indítás `ugry65` actorra, teljes SHA-ra, UAT-hivatkozásra és pontos megerősítő szövegre korlátozott, de ez nem GitHub reviewer jóváhagyás. Required reviewers és bypass szabály tényleges beállítása, valamint a szükséges scoped hitelesítő adatok jóváhagyott elhelyezése előtt a release NO-GO.

## Secret-scope

A production release workflow `Production – ahely-booking` Environmentben keresi a `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `PRODUCTION_VERCEL_PROJECT_ID` secretet és a `PRODUCTION_SUPABASE_PROJECT_REF`, `PRODUCTION_SITE_URL` variable-t. Ezeket az új environmentben még külön igazolni és szükség szerint beállítani kell, kizárólag projektgazdai jóváhagyással. A meglévő `production` nevű environmentet más production DB/backup workflow-k használják; a két environmentet nem szabad azonosnak feltételezni.

A token jogosultsága a Vercel team/project elérését biztosítja; a GitHub Environment csak a token kiadását védi. A production Vercel Supabase service-role, DB URL, SMTP és CRON secretjeinek Preview/Development scope-ját külön, titokértékek kiírása nélkül ellenőrizni kell. Staging scope-ba production secret nem kerülhet. A száraz futás a tényleges production Vercel projektből olvassa a konfigurációt, és fail-closed módon ellenőrzi a project ID-t, az org ID-t, a Supabase URL-t, a canonical site URL-t és a két Supabase kulcs jelenlétét. Nem végez deployt és nem módosítja a production konfigurációt.

**Read-only scope audit, 2026-09-28:** a production projekt Production változólistájában a `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `SMTP_PASS` és az alkalmazás URL/kulcs változói Production hatókörűek. Ugyanennek a projektnek a Preview listájában van általános Preview és `staging` ágra célzott `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, illetve `SMTP_PASS` bejegyzés is. A titokértékeket nem nyitottuk meg, így **nem igazolt**, hogy az általános Preview érték production vagy staging hitelesítő adat-e. Az általános Preview scope minden nem külön rendelt feature ágra érvényes lehet. Az értékek eredetét biztonságos, titkokat naplóba nem író eljárással kell igazolni; addig a production hitelesítő adatok Preview-ból kizárása nincs bizonyítva és az aktiválás NO-GO. A scope audit nem módosított Vercel beállítást.

## Release és rollback operátori jegyzőkönyv

1. Jegyezd fel a kiinduló production deployment ID-t, Git SHA-t, a `main` SHA-t és a production/staging deployment queue állapotát. Az aktiválás alatt `main` merge stop.
2. A `main` release SHA legyen teljes 40 karakter, CI PASS, és a release ellenőrzésekor is egyezzen a `main` HEAD-del. A staging Vercel projekt production targetje ugyanezt a SHA-t `main` refből READY állapotban futtassa; az UAT issue/PR URL-je a SHA-t és deployment ID-t tartalmazza. Az UAT és a release között a `main` befagyasztandó; új merge után ismételt staging ellenőrzés szükséges.
3. A workflow `dry-run` módban a fenti azonosságokat és a productionből lekért runtime környezetet ellenőrzi. Ha secret/reviewer vagy scope hiányzik, NO-GO. `deploy` mód jelenleg szándékosan leáll.
4. Külön jóváhagyott aktiválás után a `production` release branch csak a korábbi production SHA-ról, majd fast-forward útvonalon mozoghat. Production branch ruleset és Vercel Branch Tracking átállítás szükséges; a jelenlegi production deploymentnek az átállás után is azonosnak kell maradnia.
5. Egy jóváhagyott release esetén a workflow summaryban rögzítendő: actor, release SHA, UAT URL, staging deployment ID, előző production deployment ID, új production deployment ID, URL és READY állapot, utána `/api/health` smoke. Ennek aktív végrehajtó lépése külön review és aktiválás nélkül nem kerülhet be.
6. Hibás kiadáskor a korábbi ismert jó deployment ID alapján Vercel Dashboardban kézi rollback/promote, külön jóváhagyással. A rollback csak alkalmazáskódot és domaint fordít vissza: adatbázis-migrációt vagy Auth konfigurációt nem. A `production` branch history és a visszaállított deployment eltérését a következő release előtt rendezni és dokumentálni kell.

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
- repository ruleset: a 2026-09-27-i történeti pillanatképben még nem volt;
- production Cron Jobs globálisan **Enabled**; ezt a release-isoláció részeként nem módosítjuk.

A 2026-09-28-i UI-ellenőrzés megerősítette, hogy a Production Branch Tracking továbbra is `main`, és minden `main` push Production Deploymentet indíthat. Emiatt sem a #242, sem a #240 PR nem merge-elhető a release-isoláció aktiválása előtt.

## Baseline egyezőség – 2026-09-27

Read-only ellenőrzés alapján a jelenleg futó production deployment Git SHA-ja és a GitHub `main` HEAD azonos:

- production deployment SHA: `5a34742d2297bd3b6ac66a73ca932ee7136e2ad5`;
- GitHub `main` HEAD: `5a34742d2297bd3b6ac66a73ca932ee7136e2ad5`.

Ez legyen a kezdeti `production` release branch létrehozási pontja. A branch létrehozása előtt újra ellenőrizni kell, hogy a production deployment nem változott.

A projektgazda 2026-09-28-án megerősítette a `main` ruleset aktiválását (PR kötelező, `Application checks` és `Release evidence` required, törlés/force push tiltva). A `production` branch védelme továbbra is külön igazolandó.


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
