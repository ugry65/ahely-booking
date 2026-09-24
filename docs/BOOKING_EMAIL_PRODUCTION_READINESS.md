> **Státuszfrissítés – 2026-09-24:** PR #176 (`48aacfb1...`) és PR #177 (`953a233d...`) is mainbe került a PR #175 után; ezek az e-mail bridge megfigyelhetőségét/dokumentációját és a staging worker biztonságos diagnosztikáját egészítették ki. A stagingen a valós provider smoke/UAT korábban sikeres volt, majd a környezetet szándékosan nem-valós-küldési üzemre állítottuk vissza, hogy fejlesztési/UAT tesztfoglalások ne küldjenek véletlenül külső levelet. Ez nem booking-funkcióhiba. A production e-mail DB-migráció és `send` aktiválás továbbra is külön jóváhagyást igényel. A runtime aktuális env-értékét e dokumentációs frissítés nem olvassa ki, ezért konkrét élő módot csak környezeti ellenőrzés után szabad állítani.

# Booking e-mail: élesítés előtti állapot és üzemeltetés

Ellenőrzés: 2026-09-21, repository main `930fd6a39056e1d652b1d055d506a2956ea3fdce` (PR #175). Ez a fájl a történeti [kiadási jegyzék](RELEASE_EVIDENCE.md) és a [korábbi staging UAT](evidence/2026-09-18-staging/BOOKING_EMAIL_RESEND_STAGING_UAT.md) mellé tartozik. A PR-ban javasolt további SQL-változásokat csak merge és külön DB-migráció után tekintsd telepítettnek.

## Szerződés és adatáramlás

A booking és az audit az elszámolás hiteles adatai. A deferred `booking_email_from_audit` trigger az auditkorrelációból **egy** immutable outbox-pillanatképet hoz létre logikai műveletenként. Az enqueue hibáját a trigger izolálja: a booking, az audit és az elszámolás megmarad, a levél elmaradhat. Ezt a `105_booking_email_rpc_enqueue.sql` valós booking-hibaregresszió ellenőrzi. Az outbox nem alternatív foglalási nyilvántartás.

A `107_booking_email_bridge_safe_warning.sql` a függvény definícióját és a deferred triggert ellenőrzi. A `scripts/test-booking-email-bridge-warning.sh` ezen felül helyi tesztadatbázison ténylegesen előidézi a bridge hibáját, a `psql` warning kimenetén ellenőrzi az adatmentes SQLSTATE-et, és összeveti a megmaradt booking/audit, valamint a hiányzó részleges outbox állapotát. A script csak a helyi Supabase tesztadatbázishoz enged csatlakozni.

A `/api/internal/booking-email-worker` percenkénti Vercel Cron GET és védett kézi POST végpont. A cron Bearer `CRON_SECRET`-tel hitelesít. `disabled`: nem claimel/nem küld; `capture`: claimel, az outbox státusza captured, de nincs valódi kézbesítés; `send`: Resend-kompatibilis SMTP-n küld, státusz/attempt/worker-run adatokat ír. A worker auth- vagy konfigurációhibára 401/503, futási hibára 500 választ ad. Az admin monitor az outbox due/retry/dead-letter/stale-lease, SMTP-auth és worker-heartbeat mutatóit jeleníti meg. A bridge figyelmeztetése (ha az új javító migráció települt) kizárólag SQLSTATE-et közöl; a worker-monitor nem lát olyan bookingot, amelynél egyáltalán nem sikerült enqueue.

**Ismert MEDIUM korlát: at-least-once delivery.** Ha a provider sikeresen fogadta a levelet, de a worker a DB completion előtt leáll, a lease lejárta után ugyanaz a job újra claimelhető; ritkán két azonos levél érkezhet. A stabil Message-ID/outbox kulcs segíti a nyomkövetést, de a provider oldali pontosan egyszeri kézbesítést nem garantálja. Ez nem booking-adatintegritási hiba. Több lehetséges levél esetén outbox ID/Message-ID, attempts és provider event alapján vizsgálj, ne törölj bookingot és ne futtass vakon újraküldést.

## Futtatókörnyezeti konfiguráció

Az alkalmazás secretértékeit sem a repositoryba, sem screenshotba/logba ne írd. A `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, szerveroldali `SUPABASE_SERVICE_ROLE_KEY` és `SITE_URL` alapalkalmazási előfeltételek; az utóbbi kettő közül a service role titok. Az alábbiak az e-mail worker változói:

| Név | Secret? | staging / production | Hiány vagy hibás érték |
| --- | --- | --- | --- |
| `BOOKING_EMAIL_MODE` | nem | mindkettő; explicit disabled a biztonságos kiindulás | hiány: disabled; ismeretlen: 503, nincs küldés |
| `BOOKING_EMAIL_BATCH_SIZE` | nem | opcionális mindkettő | hiány: 10; 1–100-on kívül 503 aktív módban |
| `BOOKING_EMAIL_LEASE_SECONDS` | nem | opcionális mindkettő | hiány: 300; 30–900-on kívül 503 aktív módban |
| `BOOKING_EMAIL_FROM` | nem, de hiteles domain | capture/send mindkettő | hiány/hibás: 503, nincs claim |
| `BOOKING_EMAIL_REPLY_TO` | nem | capture/send mindkettő | hiány/hibás: 503, nincs claim |
| `BOOKING_EMAIL_MESSAGE_ID_DOMAIN` | nem | opcionális mindkettő | hiány: a-hely.com; hibás: 503, nincs claim |
| `CRON_SECRET` | **igen** | mindkettő, worker route eléréséhez | hiány vagy <32 bájt: 503; hibás Bearer: 401; nincs claim |
| `SMTP_HOST` | nem | csak send mindkettő | hiány: 503, nincs claim |
| `SMTP_PORT` | nem | send mindkettő; opcionális | hiány: 465; hibás: 503 |
| `SMTP_SECURE` | nem | csak send mindkettő | hiány/hibás: 503 |
| `SMTP_USER` | általában nem, szolgáltatótól függ | csak send mindkettő | hiány: 503 |
| `SMTP_PASS` | **igen** | csak send mindkettő | hiány: 503; rossz: retry/dead-letter vagy provider hiba |

Az aktív worker csak a konfiguráció sikeres validálása után claimel. A bridge viszont `disabled` állapotban is létrehozza az outboxot, ha a DB-migráció telepített; a későbbi `send` a **korábban felgyűlt pending** sorokat is elküldheti. Ezért bekapcsolás előtt kizárólag read-only módon ellenőrizd a pending/due mennyiséget és a címzettek körét, és külön döntsd el a felgyűlt sorok kezelését. A production `BOOKING_EMAIL_MODE` tényleges értéke ebben az auditban **nincs igazolva**; a code default disabled önmagában nem bizonyítja a telepített konfigurációt.

## Verifikált állapot és korlát

- GitHub main és PR #175 merge SHA: `930fd6a...`; a merge utáni Application checks, Database tests, Release evidence: PASS.
- A négy Vercel projekt (`ahely-booking`, `ahely-booking-staging-web`, `ahely-booking-kveb`, `ahely-booking-541h`) latest READY deploymentjének Git SHA-ja egyezik a mainnel. A Vercel target `production` a staging-web projekt esetén a **projekt deployment környezete**, nem a Supabase production DB bizonyítéka. A tényleges env értékek nem voltak ellenőrizhetők; ezt ne tekintsd küldési engedélynek.
- Staging read-only outbox-pillanatkép (2026-09-21): 16 captured, 5 sent, **1 pending**; a pending címzett nem a tesztekhez használt `.invalid` tartományú. A címzett értékét nem kértem le. A staging send mód vagy kézi worker futtatása előtt az egy pending tétel címzettjét és kezelését projektgazdai döntéssel tisztázni kell; ellenkező esetben valós külső levél távozhat.
- A három e-mail migráció jelen van a repositoryban és a CI újraépített adatbázisában (Database tests PASS). A Supabase staging migrációlistájában mindhárom szerepel, a bridge trigger ténylegesen jelen van. A Supabase production migrációlistájában **egyik sincs**, az outbox és trigger sem létezik. Production DB változtatás csak külön engedéllyel.
- A jelen PR-ban javasolt biztonságos SQLSTATE warning új migráció; staging/production adatbázisban addig **nem alkalmazott**, amíg külön jóváhagyott DB deployment nem fut.
- Korábbi 2026-09-10-i staging valódi Resend PASS: admin create/update/cancel tulajdonosnak, helyes levéltartalom. Történeti teszt, nem a main merge utáni új SHA teljes provider UAT-ja.

## Célzott staging UAT (új küldés csak külön jóváhagyással)

1. Rögzítsd a staging deployment SHA-t, a staging DB-migrációk verzióit és csak a runtime változók **létezését/módját**, titok nélkül. A workerhez staging teszt SMTP és kizárólag kontrollált tesztcímzettek kellenek. A staging alkalmazás melyik Supabase projekthez kötött, read-only módon igazolandó.
2. Vedd fel a kiinduló pending/due/retry/dead-letter számokat, utolsó worker success időt és a tesztfiókok ID-jait. A korábbi staging Resend UAT create/update/cancel eredményét őrizd meg, csak az új SHA-hoz szükséges célzott eseteket végezd újra.
3. Külön jóváhagyás után `send` kontrollált stagingen: user create, update, cancel; admin owner nevében create; recurring create, occurrence/following/series update és cancel. Minden művelet után ellenőrizd a booking és audit fennmaradását, a pontos címzettet (owner, nem admin), subjectet, Budapest dátum/időt, helyiséget, booking címet, scope-ot; e-mailben semmilyen booking note/secret ne legyen.
4. Egyeztesd a logikai művelethez tartozó outbox, attempts, worker-run és provider esemény darabszámát. Azonos outbox ID stabil Message-ID-t ad; idempotens booking RPC retry ne hozzon létre új logikai jobot. A stabil Message-ID nem bizonyítja az egyszeri kézbesítést crash esetén.
5. Hibateszt: kontrollált tesztcímzettel vagy izolált providerhibával booking létrehozás/módosítás, majd igazold hogy booking és audit megmaradt, az e-mail külön retry/dead-letter. DB bridge hiba tesztje külön (CI pgTAP); staging adatmódosítás ne sértse valós usert. Vizsgáld az utolsó worker heartbeatot, stale lease-t, dead-letter láthatóságát és az érzékeny adatmentes figyelmeztetést.
6. Rögzítsd a timestampet, SHA-kat, outbox IDs/Message-ID-ket maszkolva, darabszámokat és PASS/FAIL-t. Ha a pending backlog több címzettet érint, **ne kapcsolj send módra** a címzettkör tisztázása nélkül.

## Production activation / leállítás

Kapu: SQL-javítás független security/data-integrity review + zöld CI és PR merge; szükséges staging DB migráció külön jóváhagyva; célzott staging provider/hiba-UAT bizonyíték; production DB migráció külön engedély és állapotellenőrzés; production env secret-nevek és konfiguráció ellenőrzése értékfelfedés nélkül; backlog/címzettkör jóváhagyása; külön production `send` engedély. Egyik sem következik a PR #175 merge-jéből.

Leállítás: incidens esetén projektgazdai engedéllyel állítsd az érintett Vercel deployment `BOOKING_EMAIL_MODE` értékét `disabled`-re és alkalmazd új deploymenttel; ellenőrizd a tényleges SHA/módot, worker no-op és outbox változatlan állapotát. Ne töröld az outboxot, auditot vagy bookingot; az elküldött levelet visszavonni nem lehet. A backlog későbbi kiküldése újabb külön döntés. Ha csak SMTP hibás, az authoritative booking továbbra is működjön; ellenőrizd ezt a monitor és booking/audit egyeztetésével.
