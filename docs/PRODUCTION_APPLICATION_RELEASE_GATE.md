# Production alkalmazás-release kapu (#241)

**Állapot 2026-09-30:** a release-isoláció konfigurációs lépései elkészültek. A production Vercel projekt Production Branch Tracking értéke `production`, a Preview Branch Tracking ki van kapcsolva. A védett `production` Git ág az ismert jó production SHA-n (`0fe5e135a264d0d340c5087ab670e97355ff29fb`) létezik. Az aktív production domain továbbra is a READY `dpl_EeA7v9CjuE4JKtgDTMZYCAuDW5Vb` deploymentre mutat ugyanezzel a SHA-val; az izoláció beállítása nem indított új production deploymentet. A #242 CI-je sikeres. Production release továbbra is külön emberi döntést igényel.

## Rövid terv

`feature → PR + CI → main → automatikus staging → staging UAT → mainból productionba irányuló, védett release PR → Imre merge-döntése → Vercel production deploy`

A production Vercel projekt Git-kapcsolata megmarad, a **Production Branch Tracking** már `production`. A production projekt Preview Branch Trackingje ki van kapcsolva; a külön staging projekt továbbra is `main`-t követ. A Vercel production-target automatikus deploymentje így a `production` ághoz kötött. A közös `vercel.json` git kapcsolóját nem módosítjuk.

Ez a megoldás nem használ új Vercel deploy tokent vagy CLI buildet. A production ágra történő **emberi PR merge maga a release döntés**. A GitHub Environment reviewer nem előfeltétele: jelenleg a `Production – ahely-booking` environment reviewer kapcsolója ki van kapcsolva, és egyetlen tulajdonos saját jóváhagyása nem független kapu.

## Release PR ellenőrzése

A `Production release gate` check csak ugyanebben a repositoryban lévő `main → production` PR-ra fut. Igazolja, hogy:

- a forrás SHA a check időpontjában a `main` HEAD;
- a PR teszt-merge fájlfája byte-pontosan azonos a `main` fájlfájával (a release merge commit SHA-ja ettől különbözhet);
- a PR törzse tartalmazza a teljes SHA-t, a staging deployment ID-t és az UAT GitHub URL-jét az alábbi pontos formában:

  ```text
  Release main SHA: <40 hex>
  Staging deployment ID: dpl_...
  Staging UAT: https://github.com/ugry65/ahely-booking/issues/<id>
  ```

A check a deployment ID **alakját** ellenőrzi, annak valódi Vercel-projekt/SHA összerendelését nem. Imre a merge előtt külön, read-only módon ellenőrzi, hogy a staging projekt Production target READY deploymentje az adott `main` SHA, az UAT pedig ezt az ID-t és a PASS eredményt rögzíti. Ha `main` vagy a staging deployment közben változik, az ellenőrzést és UAT-t meg kell ismételni. A kapu a `node scripts/check-release-evidence.mjs --release` parancsot is futtatja. A booking-email szolgáltatás jóváhagyott állapota `disabled_by_business_decision` ([döntés](BOOKING_EMAIL_BUSINESS_DECISION_2026-09-30.md)); a négy korábbi e-mail blokk változatlanul külön activation check. Amíg a jóváhagyott mód `disabled`, ezek és a Vercel runtime mód külön API-s megfigyelésének hiánya **nem blokkolják az általános alkalmazás-release-t**. `capture` vagy `send` aktiváláskor viszont kötelező a production runtime mód read-only bizonyítéka és mind a négy activation check bizonyított lezárása. A #241 nem minősíti az e-mail élesítést késznek. A release PR-on a `Production release gate`, `Application checks` és `Release evidence` státusz legyen kötelező és sikeres. Ezt GitHub rulesetben külön be kell állítani.

A Vercel production-target build a `next.config.ts` betöltésekor a rendszer által adott project ID-t és Git refet, valamint a tényleges Supabase URL-t és `SITE_URL` értéket együtt ellenőrzi. A production projekt kizárólag `production` ággal, `yasrmxwjojepessivhmc` Supabase projekttel és `https://foglalas.a-hely.com` site URL-lel, a staging projekt kizárólag `main` ággal, `fvwapntzhavhgazeflri` projekttel és a staging URL-lel épülhet. Hiányzó vagy eltérő értéknél a build leáll. A Vercel System Environment Variables kapcsoló mindkét projekten bekapcsolt állapotúnak látszik a 2026-09-28-i read-only UI-ellenőrzésben; a tényleges éles build-változókat csak az aktiváláskor lehet igazolni. A Preview scope külön kezelendő.

Az admin AllBooked import route production Supabase refet (`yasrmxwjojepessivhmc`), Vercel production környezetet és `main` vagy `production` Git refet követel. A staging import kizárólag a staging Supabase refet (`fvwapntzhavhgazeflri`) és `main` refet fogad el. A ref önmagában nem környezetazonosság; minden feltétel együtt szükséges. A #258 a történeti `void-papp-dalma-test-import` route-ot eltávolította, és forward-only migrációval kivezette a hozzá tartozó RPC-t; a #241 integráció ezt megőrzi. A `production` ág engedése a mainen futó régi alkalmazás viselkedését nem változtatja, de az éles átállás előtt célzott staging ellenőrzés szükséges.

## Bevezetési sorrend – Imre külön jóváhagyásával

1. Rögzítsük frissen a production és staging deployment ID, Git SHA, domain és health állapotát. Állítsuk meg a `main` merge-eket az átállási ablakra; ellenőrizzük a deployment queue-t.
2. Read-only audit: production Vercel Preview/Development változókban látható `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `SMTP_PASS` eredetét titokértékek naplózása nélkül tisztázni kell. Az általános Preview és `staging` ágra célzott bejegyzések léteznek; jelenleg **nem bizonyított**, hogy nincs production secret Preview-ban. A `production` ág létrehozása a jelenlegi beállítás mellett is Preview deployt indíthatna a production projektben. A GitHub repo/org és Environment secret scope-okat is egyeztetni kell. Eltérés esetén NO-GO.
3. Imre külön, az alábbi pontos sorrendre adott jóváhagyása után: először kapcsoljuk ki **csak a production Vercel projekt** Preview Branch Tracking kapcsolóját; ellenőrizzük, hogy a domain és az aktív production deployment nem változott. Ezután hozzuk létre a `production` Git ágat az aktiváláskor igazolt aktív production SHA-n, állítsuk be rögtön a rulesetet (PR kötelező, `Production release gate`, `Application checks`, `Release evidence` required, force push és deletion tiltott, bypass nélkül), majd a production Vercel projekt Production Branch Tracking értékét állítsuk `production`-ra. Ellenőrizzük, hogy sem a branch létrehozása, sem a követésváltás nem hozott létre production deployt és nem változtatta a domain aktív deploymentjét. Eltérésnél állj meg. A staging projekt egyik ágkövetése sem változik.
4. Csak az izoláció tényleges read-only bizonyítása után merge-elhető a #242 mainbe. A staging automatikus `main` deploymentjét, a production változatlanságát és a pontos SHA-t külön igazoljuk. Ezután staging UAT.
5. Imre pontos SHA-ra és staging deployment ID-ra hagyja jóvá a `main → production` PR merge-et. A PR merge commitja a `production` ág új SHA-ja; a CI előzőleg azonos fájlfát igazolt. Vercel deployment listában ellenőrizzük a READY állapotot, a production project ID-t (`prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo`), Git SHA-t/refet és deployment ID-t. Rögzítsük az előző deployment ID-t is. Canonical URL és `/api/health` smoke; admin importot **nem** hajtunk végre ellenőrzés céljából.
6. Hiba esetén az előző ismert jó deploymentet Vercel Dashboardból kézi rollback/promote művelettel állítsuk vissza, külön jóváhagyással. Ez alkalmazáskódot/domain alias-t fordít vissza; adatbázis/Auth migrációt nem. A release PR, staging SHA, production merge SHA, Vercel ID/URL, UAT és rollback döntés együtt adja az auditnaplót.

**Fontos korlát:** az egyetlen Vercel tulajdonos közvetlen Dashboardból továbbra is tud kézi deployt indítani; a GitHub ruleset ezt nem akadályozza. A folyamat az engedélyezett operátori release út auditját adja, nem műszaki garancia minden tulajdonosi megkerülés ellen. Az éles konfiguráció módosítására 100%-os zavartalansági garancia nem adható; ezért az éles lépések előtt külön döntés szükséges.

## Staging próbák és nyitott kapuk

2026-09-28-án a csak `ahely-booking-staging-web` projektre jogosult, 1 órás token a staging Vercel REST API GET műveletére HTTP 200-at, a production projektére 404-et adott. A `vercel@60.1.3 pull` ezzel a szűk tokennel nem működött; build/deploy nem történt. A tokent visszavontuk (staging API utána 403), helyi példányát töröltük. A CLI-s release változatot ezért elvetettük.

Ugyanezen a napon a staging projekt Production Branch Tracking értékét röviden a #241 feature ágra állítottuk, majd `main`-re visszaállítottuk. A Vercel mindkét mentést visszaigazolta, és külön redeployt ajánlott; redeployt nem indítottunk. Ez a beállítás szerkeszthetőségét bizonyítja, nem a production release ág tényleges deployját. A buildazonosság helyi tesztje staging és production célkonfigurációval PASS, keresztezett staging/production Supabase URL-lel fail-closed. A staging projekt jelenlegi `main` deploymentje READY állapotban igazolt. A production Preview privileged-secret scope teljes auditja külön hardening feladat; a production projekt Preview Branch Trackingje időközben ki lett kapcsolva.

A production Cron Jobs globálisan továbbra is engedélyezett. `BOOKING_EMAIL_MODE=disabled`; a booking-email worker még meghívódhat, de nem küld booking levelet. A #240 fogja a percenkénti worker cront eltávolítani; a benne lévő, globális Cron Jobs kikapcsolásról szóló dokumentációs állítást külön javítani kell. A #240 merge tilos, amíg #241 izoláció nem bizonyított.

**GitHub secret scope read-only eredmény:** a `Production – ahely-booking` új environmentben nincs release token. A régi `Production` és `staging` environment külön secretkészlet. A GitHub `staging` environmentben `SUPABASE_PRODUCTION_DB_URL` és `SUPABASE_PRODUCTION_SERVICE_ROLE_KEY` nevű secret is szerepel (a meglévő backup/restore tesztfolyamatok miatt); a repository scope-ban backup-titkok vannak. Az új `Production release gate` workflow nem kér environmentet és nem hivatkozik ezekre a secretekre. Ez nem igazolja a Vercel Preview titokértékeit, és nem engedélyez módosítást a meglévő backup/DB workflow-kon.

**Vercel Preview állapot:** a production projekt Preview Branch Trackingje 2026-09-30-án ki lett kapcsolva. Korábbi read-only ellenőrzés szerint a `SUPABASE_SERVICE_ROLE_KEY` három Preview scope-ban szerepelt: általános, `staging`, illetve `feature/107-booking-email-outbox` ág. A secret értékét a lista nem fedte fel, ezért az eredetük és a régi Preview deploymentek külön hardening/audit témák maradnak. A tracking kikapcsolása a jövőbeli automatikus Preview deployokat megállítja, de a korábban létrejött scope-okat nem törli.
