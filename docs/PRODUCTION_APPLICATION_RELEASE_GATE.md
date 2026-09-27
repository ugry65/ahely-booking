# Production alkalmazás-release kapu – technikai terv

**Dátum:** 2026-09-27  
**Issue:** #241  
**Állapot:** előkészítés; production konfigurációt ez a változtatás nem módosít.

## Célfolyamat

`feature branch → PR/CI → main → automatikus staging → staging UAT → explicit production jóváhagyás → production deploy`

A production alkalmazás nem kerülhet automatikusan élesbe pusztán attól, hogy egy commit bekerül a `main` ágba.

## Biztonsági alapelv

A production Vercel projekt Git-alapú automatikus deployját projekt-szinten kell megszüntetni. Ezt **nem** szabad a közös `vercel.json` `git.deploymentEnabled` mezőjével megoldani, mert ugyanazt a fájlt a staging projekt is használja.

A jelenlegi éles deployment addig változatlan marad, amíg a projektgazda külön nem hagyja jóvá a production Vercel beállítás módosítását.

## Javasolt release-kapu

1. PR CI legyen zöld.
2. Merge `main`-be.
3. Staging Vercel automatikusan deployolja a `main` commitot.
4. Staging UAT/smoke PASS.
5. Production release workflow kizárólag kézi `workflow_dispatch` indítással fusson.
6. A workflow pontos megerősítő szöveget kérjen: `DEPLOY-PRODUCTION`.
7. A workflow `environment: production` alatt fusson.
8. Release előtt ellenőrizze:
   - a megadott SHA létezik és a `main` történetének része;
   - a production Vercel project ID pontosan `prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo`;
   - a production Supabase project ref pontosan `yasrmxwjojepessivhmc`;
   - a production site URL pontosan `https://foglalas.a-hely.com`;
   - a szükséges production secret-ek rendelkezésre állnak.
9. A workflow először build/deployment jelöltet készítsen, majd csak explicit kapun keresztül állítsa productionre.
10. A deployolt commit SHA és Vercel deployment ID/URL auditálhatóan jelenjen meg a workflow summaryban/release evidence-ben.
11. Deploy után célzott production smoke: canonical URL + `/api/health`.
12. Hiba esetén a korábbi ismert jó deploymentre történő rollback legyen dokumentált és kézi jóváhagyású.

## Production Vercel projekt átállítása

Csak a fenti workflow staging/száraz ellenőrzése után, külön projektgazdai jóváhagyással:

- production Vercel projekt automatikus Git deploymentjének projekt-szintű letiltása / Git kapcsolat kontrollált leválasztása;
- staging Git kapcsolat változatlan marad;
- ellenőrizni kell, hogy a jelenlegi production deployment és custom domain továbbra is kiszolgál;
- egy próba main commit után igazolni kell: staging deploy történik, production automatikus deploy NEM történik;
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
