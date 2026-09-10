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
- `UAT_RESET_EMAIL` — egy valósan elérhető teszt-email, amely kizárólag USER-RESET lesz a jelszó-visszaállítás UAT-jához;
- `UAT_SHARED_PASSWORD` — legalább 12 karakteres, kizárólag staging UAT jelszó.

A többi Auth user `.invalid` végződésű szintetikus címet kap, ezért valódi emailt nem küldünk nekik.

Létrejövő identitások:

- `ADMIN-1`: `uat-admin@ahely.invalid`, aktív admin;
- `USER-A`: `uat-user-a@ahely.invalid`, aktív, determinisztikus normál tesztuser;
- `USER-B`: `uat-user-b@ahely.invalid`, aktív normál user;
- `USER-HIDDEN`: `uat-hidden@ahely.invalid`, aktív normál user, maszkolási teszt foglalója;
- `USER-INACTIVE`: `uat-inactive@ahely.invalid`, inaktív normál user.
- `USER-RESET`: `UAT_RESET_EMAIL`, valósan elérhető email kizárólag a jelszó-visszaállítás tesztjéhez.

A bootstrap a már létező USER-RESET Auth-identitást, profilt, jelszót, csoporttagságot és helyiségjogot nem módosítja. Ha az identitás még nem létezik, egyszer létrehozza; későbbi futáskor változatlanul hagyja. A szintetikus USER-A ettől teljesen elkülönül.

A névláthatóság jelenlegi kanonikus szabálya globális adminbeállítás. A manuális UAT során a `Más foglalók neve látható` beállítást külön BE/KI állapotban kell ellenőrizni: kikapcsolva normál user másoknál csak semleges `Foglalt` megjelenítést kap, admin továbbra is látja a foglaló nevét és stabil színét.

## UAT helyiségek és jogok

A bootstrap legalább az alábbi helyiségeket biztosítja:

- Tréningterem;
- 1.Szoba-családi;
- 2.Szoba;
- 3.Szoba;
- 4.Szoba — USER-A számára tiltott kontrollhelyiség.

USER-A több normál helyiséghez és a Tréningteremhez kap foglalási jogot. Az ismétlődő foglalási jogosultság kanonikus forrása user-szintű (`profiles.can_repeat_bookings`), nem helyiségenkénti `can_repeat` flag. A csoporttagság és a közvetlen user–szoba kivételjog csak az effektív `can_book` jogot adja; normál user Tréningteremben repeat joggal sem ismételhet. USER-B eltérő jogkombinációt kap. USER-INACTIVE kap szintetikus helyiségjogot is, hogy az inaktív profil backend tiltása önállóan bizonyítható legyen.

A bootstrap minden szintetikus UAT-identitás korábbi közvetlen helyiségjogát visszavonja, csoporttagságát eltávolítja, majd az előírt tesztjogokat újra létrehozza. Ehhez a meglévő auditált admin RPC-ket használja, nem kap új közvetlen service-role DELETE/EXECUTE jogosultságot. A verify az admin hozzáférési read-modelből USER-A teljes effektív jogosultsághalmazát állítja elő, ezért a közvetlen és a csoportból örökölt váratlan jogot is hibának jelzi. USER-RESET adatai és jogosultságai ebből a tisztításból kötelezően kimaradnak.

Az A-Hely üzleti szabálya szerint nincs globális zárt nap vagy általános naptári kivételdátum. A bootstrap ezért nem hoz létre `calendar_exceptions` tesztadatot. Ez nem érinti az ismétlődő sorozat user által választott kihagyott/kivétel alkalmait.

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
7. staging weben ADMIN-1 és a szintetikus USER-A login smoke.
8. USER-A nem láthat admin navigációt.
9. ezután indulhat a `docs/FUNKCIONALIS_UAT_CHECKLIST.md` teljes manuális futása.

A #36 csak akkor zárható, ha a 4–8. pont végrehajtásáról tényleges bizonyíték rendelkezésre áll; a workflow puszta megléte nem elég.

## Scope-határ

Ez a bootstrap nem production deploy, nem backup automatizálás, nem pénzügyi modul és nem production felhasználó-import. A service-role használata kizárólag staging tesztidentitások és szintetikus UAT-konfiguráció reprodukálható előkészítésére szolgál; az alkalmazás normál üzleti írási útvonalait nem helyettesíti.
