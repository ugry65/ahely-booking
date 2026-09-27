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
