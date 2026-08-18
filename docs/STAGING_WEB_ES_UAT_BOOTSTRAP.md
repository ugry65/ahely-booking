# Staging webalkalmazás és UAT bootstrap

Kapcsolódó issue-k: #32, #36

## Cél

A funkcionális UAT kizárólag productiontól elkülönített staging környezetben fusson. A staging adatbázis a `ahely-booking-staging` Supabase projekt (`fvwapntzhavhgazeflri`), a webalkalmazás pedig külön Vercel staging projekt legyen.

Production adat, production Supabase kulcs vagy production felhasználó stagingbe másolása tilos.

## Adatbázis-előfeltétel

Az UAT bootstrap csak akkor indítható, ha a staging migration history teljesen egyezik a repository-val. A #34 teljesítésekor 14/14 migráció került stagingre.

## Staging webalkalmazás

A Vercelben külön projektet kell létrehozni ehhez a repository-hoz. A staging projekt kizárólag az alábbi Supabase projektre mutathat:

- URL: `https://fvwapntzhavhgazeflri.supabase.co`
- project ref: `fvwapntzhavhgazeflri`

Kötelező Vercel environment változók/secretek:

- `NEXT_PUBLIC_SUPABASE_URL` — staging URL;
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — staging publishable key;
- `SUPABASE_SERVICE_ROLE_KEY` — staging service role, kizárólag szerveroldalon;
- `SITE_URL` — a stabil staging web URL.

A `SUPABASE_SERVICE_ROLE_KEY` soha nem kaphat `NEXT_PUBLIC_` előtagot.

A Supabase Auth Site URL és redirect URL csak a stabil staging URL-t tartalmazza. Preview URL csak konkrét UAT-igény esetén engedélyezhető.

## Reprodukálható szintetikus UAT identitások

A manuális workflow: `.github/workflows/staging-uat-bootstrap.yml`.

Alapértelmezett módja `verify`; adatot csak explicit `bootstrap` input esetén hoz létre/módosít.

A workflow három staging Environment secretet igényel:

- `SUPABASE_STAGING_SERVICE_ROLE_KEY` — kizárólag a staging projekt service-role kulcsa;
- `UAT_RESET_EMAIL` — egy valósan elérhető teszt-email, amely USER-A lesz, a jelszó-reset UAT-hoz;
- `UAT_SHARED_PASSWORD` — legalább 12 karakteres, kizárólag staging UAT jelszó.

A többi Auth user `.invalid` végződésű szintetikus címet kap, ezért valódi emailt nem küldünk nekik.

Létrejövő identitások:

- `ADMIN-1`: `uat-admin@ahely.invalid`, aktív admin;
- `USER-A`: `UAT_RESET_EMAIL`, aktív normál user, más foglalók neveinek megjelenítése kikapcsolva;
- `USER-B`: `uat-user-b@ahely.invalid`, aktív normál user;
- `USER-HIDDEN`: `uat-hidden@ahely.invalid`, aktív normál user, maszkolási teszt foglalója;
- `USER-INACTIVE`: `uat-inactive@ahely.invalid`, inaktív normál user.

A névláthatóság a megtekintő profilbeállítása. A bootstrap nem hoz létre foglalást ehhez a teszthez: a **manuális UAT során** USER-HIDDEN hoz létre egy foglalást, miközben USER-A `other_booker_names_visible=false` beállítással nézi a naptárt; admin továbbra is teljes nevet lát.

## UAT helyiségek és jogok

A bootstrap legalább az alábbi helyiségeket biztosítja:

- Tréningterem;
- 1.Szoba-családi;
- 2.Szoba;
- 3.Szoba;
- 4.Szoba — USER-A számára tiltott kontrollhelyiség.

USER-A több normál helyiséghez és a Tréningteremhez kap foglalási jogot, de ismétlési joga csak kijelölt normál helyiségre van. USER-B eltérő jogkombinációt kap. USER-INACTIVE kap szintetikus helyiségjogot is, hogy az inaktív profil backend tiltása önállóan bizonyítható legyen.

A bootstrap létrehoz egy, a futás napjához képest kb. 20 nappal későbbi zárt kivételdátumot `UAT zárt kivételdátum` indokkal.

## Fail-closed védelem

A bootstrap script keményen ellenőrzi a Supabase URL-t. Csak a `fvwapntzhavhgazeflri` staging projekt ellen hajlandó futni; más URL esetén azonnal hibával leáll.

A workflow kizárólag a GitHub `staging` Environmentet használja. Production secret vagy production project ref nincs benne. A `workflow_dispatch` input nem kerül közvetlen `${{ }}` szöveghelyettesítéssel shell-parancsba: a `mode` értéket környezeti változó viszi át a Node scriptnek, amely külön `verify|bootstrap` allowlistet is ellenőriz.

## Futtatási sorrend

1. Vercel staging projekt létrehozása és environment változók beállítása.
2. Supabase Auth staging Site URL / redirect URL beállítása.
3. GitHub `staging` Environmentben a három UAT secret beállítása.
4. `Staging UAT bootstrap` workflow `verify` módban — első alkalommal várhatóan hibázik, mert még nincs UAT adat.
5. `bootstrap` explicit futtatása.
6. új `verify` futásnak zöldnek kell lennie.
7. staging weben ADMIN-1 és USER-A login smoke.
8. USER-A nem láthat admin navigációt.
9. ezután indulhat a `docs/FUNKCIONALIS_UAT_CHECKLIST.md` teljes manuális futása.

A #36 csak akkor zárható, ha a 4–8. pont végrehajtásáról tényleges bizonyíték rendelkezésre áll; a workflow puszta megléte nem elég.

## Scope-határ

Ez a bootstrap nem production deploy, nem backup automatizálás, nem pénzügyi modul és nem production felhasználó-import. A service-role használata kizárólag staging tesztidentitások és szintetikus UAT-konfiguráció reprodukálható előkészítésére szolgál; az alkalmazás normál üzleti írási útvonalait nem helyettesíti.
