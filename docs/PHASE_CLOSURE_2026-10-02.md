# Fejlesztési fázis lezárási állapot – 2026-10-02

## Cél
Ez a dokumentum a 2026-10-02-án lezárt fejlesztési fázis aktuális átadási pontja. Új beszélgetés vagy későbbi fejlesztés esetén ezt, a projektkontextust, a technikai architektúrát és a repository aktuális main/production ágát együtt kell elsődleges forrásként használni.

## Aktuális környezet és release-modell
- Kódforrás: GitHub `ugry65/ahely-booking`.
- `main`: staging kiadási ág; automatikusan a külön staging Vercel projektre települ.
- `production`: kizárólag explicit, ellenőrzött main → production PR után települ.
- Staging: `https://ahely-booking-staging-web.vercel.app`.
- Production: `https://foglalas.a-hely.com`.
- Production Vercel projekt nem követi automatikusan a main ágat.
- Production release gate: exact main SHA + staging deployment ID + GitHub UAT bizonyíték + application/release-evidence check.
- Single-owner repository miatt kötelező külső GitHub approval nincs; a release kapu és explicit projektgazdai production-jóváhagyás marad kötelező.

## Production állapot a fázis végén
A 2026-10-01-i production release-ek után éles:
- havi settlement kézi, immutable revision alapú lezárás/publikálás;
- lezárt havi összeg megjelenítése a user saját Foglalásaim oldalán;
- havi sáv kiválasztása az összes aktív elszámolandó havi órából, a Tréningterem csoportos órákat is beleszámítva; a csoportos tétel saját speciális díja változatlan;
- Alkalmi Egyéni / Alkalmi Csoport havi összesítő sorok;
- alkalmi ügyfelek `booking_title` szerinti havi összevonása, ügyfelenként óra, óradíj és fizetendő összeg;
- névnormalizálás: case, whitespace, ékezetelt/ékezet nélküli alak, valamint konzervatív egykarakteres elütés hosszabb és egyébként egyértelműen egyező névnél;
- rövid/hasonló, de nem egyértelmű neveket a rendszer szándékosan nem von össze automatikusan;
- a megjelenítés nem írja át a lezárt settlement revisionöket.

Utolsó production release commit a fázisban: `16aedc1ca322f88bc8b6aee81eae31f250d2885c` (#272). A deployment READY és a production health endpoint 2026-10-01-én HTTP 200 / database ok eredményt adott.

## Adatbiztonsági baseline
Változatlanul kötelező:
- DB-szintű foglalási ütközésvédelem;
- tranzakciós kritikus írások;
- backend/RLS jogosultságellenőrzés;
- auditálható törlés, korrekció és settlement revision;
- backup + visszaállíthatóság;
- production DB/env változtatás csak külön jóváhagyással;
- lezárt pénzügyi snapshot automatikusan nem írható át.

## Booking e-mail
Üzleti döntés: booking create/update/cancel e-mail jelenleg nem része az aktív production szolgáltatásnak; kívánt mód `BOOKING_EMAIL_MODE=disabled`. A Supabase Auth jelszóbeállítás/jelszó-visszaállítás e-mail ettől külön rendszer.
A worker/outbox kód megmarad későbbi aktiválhatóság miatt. Aktiválás előtt backlog/címzett, provider és runtime konfiguráció külön ellenőrzendő.
A percenkénti booking-email worker cron #274-ben eltávolítva a `vercel.json`-ból; a négy production-health cron változatlan. A worker/outbox kód megmaradt.

## Tudatosan nyitva hagyott backlog
- #238: password recovery URL/template contract hibajegy. Lezárás előtt aktuális staging/production állapotot végponttól végpontig újra kell igazolni; a ticket jelenleg nyitott.
- #239: booking-email worker cron eltávolítása; üzleti e-mail mód továbbra is disabled.
- #254: alkalmi elszámolás következő pénzügyi fázisa. A read-only/összesítő UI elkészült; a fizetés/számlázás írási modellje nincs kész.
  - Aktuális üzleti döntés: Fizetve/Számlázva állapot alkalmi foglalónként és hónaponként kezelendő az elszámolási összesítésben.
  - Nem bookingonkénti checkbox és nem írhatja felül a normál userek meglévő részfizetéses pénzügyi modelljét.
  - Backend audit: ki és mikor módosította.
- Későbbi, nem fáziszáró témák: statisztika/kihasználtság, számlázó-integráció, további riportok, opcionális PWA/UX finomítások.

## Issue/PR higiénia
2026-10-02-án lezárva mint bizonyítottan teljesített: #241 (release isolation), #245 (admin modal feedback), #248 (Migráció menüpont eltávolítás).
Régi, superseded/elhagyott nyitott PR-ek lezárhatók/lezárásra kerültek; a repository aktuális mainje az implementáció hiteles forrása.

## Újrakezdési protokoll
Későbbi fejlesztés előtt:
1. olvasd el ezt a fájlt és a gyökér projektkontextust;
2. ellenőrizd a main és production aktuális SHA-ját;
3. nézd át a nyitott issue-kat, különösen #238, #239, #254;
4. ellenőrizd, hogy az új igény módosít-e üzleti/pénzügyi szabályt;
5. feature branch → CI → main/staging → UAT → explicit production release;
6. kritikus pénzügyi, jogosultsági, backup vagy konkurencia-változásnál független review szükséges.

## Fáziszárási minősítés
A jelenlegi booking + havi elszámolási megjelenítési fázis lezárható. Nincs ismert, dokumentálatlan adatvesztési vagy settlement-integritási probléma. A fent felsorolt nyitott tételek elkülönített backlogként maradnak, és nem tekintendők elkészültnek.
