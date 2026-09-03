# Foglalási e-mail értesítések – transactional outbox döntés

Állapot: **elfogadott technikai irány; az adatbázis-alapréteg implementálva a draft ágon, staging alkalmazás és szolgáltatói UAT előtt**

Dátum: 2026-09-03

Kapcsolódó GitHub issue: #107

## 1. Kötelező üzleti viselkedés

A foglalás tulajdonosa minden sikeres foglalási művelet után e-mailt kap:

- egyedi foglalás létrehozása;
- egyedi foglalás módosítása;
- egyedi foglalás lemondása;
- ismétlődő sorozat létrehozása;
- sorozat `occurrence`, `following` vagy `series` hatókörű módosítása és lemondása.

Admin által más nevében végzett műveletnél is mindig a foglalás tulajdonosa a címzett, és a levél jelzi, hogy admin végezte a műveletet. Egy logikai sorozatművelethez pontosan egy összefoglaló értesítési feladat tartozik, nem alkalmanként egy.

Az e-mail-szolgáltató hibája nem gördítheti vissza és nem veszélyeztetheti a sikeresen mentett foglalást. A kiküldési kötelezettség ugyanabban az adatbázis-tranzakcióban, tartósan rögzül.

## 2. Kiinduló forrásaudit

A jelenlegi rendszerben már létezik az általános `public.outbox_events` tábla, és az egyedi create/update/cancel RPC-k outbox eseményt hoznak létre. Ez azonban közvetlen e-mail-küldésre nem alkalmas:

- a payload nem tartalmazza az eseménykori, megjelenítéshez szükséges teljes és változtathatatlan adatpillanatot;
- az actor/admin jelzés és a foglalási művelet korrelációja nem minden eseményben áll rendelkezésre;
- sorozat létrehozásakor és scope-műveletnél alkalmanként külön esemény keletkezik, miközben az üzleti döntés egy összefoglaló levél;
- nincs lease-alapú claim, állapotgép, dead-letter állapot, append-only próbálkozásnapló és deduplikációs kulcs;
- a staging adatbázisban 2026-09-03-án 135 feldolgozatlan legacy esemény volt: 109 create, 10 update és 16 cancel.

Ezért a worker **nem olvashatja közvetlenül a legacy `outbox_events` rekordokat**. Ezeket megőrizzük, de nem migráljuk automatikusan e-mail-feladattá és nem küldjük ki utólag.

## 3. Választott architektúra

### 3.1 Külön e-mail outbox

Új, célzott `public.booking_email_outbox` tábla készül. Az értesítési rekordot maga a kanonikus booking RPC hozza létre a booking- és auditmódosítással azonos tranzakcióban.

Javasolt mezők:

| Mező | Szerep |
| --- | --- |
| `id uuid` | Stabil esemény- és Message-ID alap |
| `correlation_id uuid` | Booking művelet audit/idempotencia-korrelációja |
| `deduplication_key text unique` | Egy logikai üzleti művelethez legfeljebb egy e-mail-feladat |
| `event_type text` | `booking.created`, `booking.updated`, `booking.cancelled` |
| `scope text` | `single`, `occurrence`, `following`, `series` |
| `booking_id uuid null` | Egyedi/occurrence művelet hivatkozása |
| `series_id uuid null` | Sorozat-összefoglaló hivatkozása |
| `recipient_user_id uuid` | Foglalástulajdonos, `ON DELETE RESTRICT` |
| `recipient_email text` | A művelet sikerének időpontjában feloldott, normalizált kanonikus cím |
| `actor_user_id uuid` | A tényleges műveletvégző, `ON DELETE RESTRICT` |
| `performed_by_admin boolean` | Levéltartalomhoz változtathatatlan adminjelzés |
| `payload_version integer` | Verziózott renderer-szerződés |
| `payload jsonb` | Minimalizált, eseménykori levéladat-pillanat |
| `status text` | `pending`, `sending`, `retry`, `sent`, `dead_letter`, `suppressed`, stagingben `captured` |
| `attempts integer` | Befejezett küldési próbálkozások száma |
| `next_attempt_at timestamptz` | Következő biztonságos retry ideje |
| `lease_token uuid`, `leased_at`, `lease_expires_at` | Konkurens workerek elleni claim |
| `sent_at timestamptz` | Sikeres SMTP-átadás ideje |
| `provider_message_id text` | Szolgáltatói/SMTP eredményazonosító |
| `last_error_code`, `last_error_safe` | Titok- és payloadmentes diagnosztika |
| `created_at`, `updated_at` | Operációs időbélyegek |

A `deduplication_key` a booking RPC meglévő korrelációs/idempotencia-azonosítójából, az eseménytípusból és a címzettből determinisztikusan készül. Ugyanazon kérés biztonságos újrafuttatása nem hozhat létre új értesítést.

A címzett címe a művelet tranzakciójában a kanonikus profilból oldódik fel. Aktív foglalástulajdonosnál a hiányzó, üres vagy nem konzisztens e-mail adat belső adatinvariáns-hiba: ilyenkor nem készülhet értesítés nélküli „sikeres” booking művelet. Ez nem külső SMTP-hiba; az SMTP elérhetőségét a booking tranzakció soha nem ellenőrzi.

### 3.2 Változtathatatlan payload

A worker nem a foglalás későbbi aktuális állapotából állítja össze a levelet. A tranzakcióban készülő payload csak a szükséges eseménykori adatokat tartalmazza:

- címzett megjelenítési neve;
- helyiség neve;
- dátum, kezdés és befejezés UTC időpontként, `Europe/Budapest` megjelenítési szabállyal;
- használat típusa;
- foglalás címe, ha van;
- update esetén a releváns korábbi és új értékek;
- cancellation esetén a lemondási ok, ha van;
- sorozatnál scope, érintett alkalmak száma, első és utolsó érintett időpont;
- adminművelet jelzése.

Foglalási megjegyzés, auth token, reset URL, service key, belső hiba stack, teljes audit payload vagy szükségtelen személyes adat nem kerül az e-mail payloadba.

### 3.3 Sorozatok leképezése

| Booking művelet | E-mail outbox rekord |
| --- | --- |
| Egyedi create/update/cancel | 1 rekord |
| Sorozat létrehozása | 1 összefoglaló rekord a sikeresen létrejött alkalmakról |
| `occurrence` update/cancel | 1 rekord az érintett alkalomról |
| `following` update/cancel | 1 összefoglaló rekord |
| `series` update/cancel | 1 összefoglaló rekord |

Az outbox insert csak az összes célbooking sikeres módosítása után történik, de még ugyanabban a tranzakcióban. Rollback esetén sem booking-részállapot, sem árva e-mail-feladat nem maradhat.

## 4. Worker és konkurenciakezelés

A küldő egy Node.js runtime-ú, belső Next.js Route Handler. A böngészőből nem hívható közvetlenül. A scheduler `Authorization: Bearer <CRON_SECRET>` fejlécét kötelezően ellenőrzi, a Supabase service role kulcs és az SMTP titkok kizárólag szerveroldali environment variable-k.

A worker kis batchben claimel rekordokat egy kizárólag `service_role` számára végrehajtható, `SECURITY DEFINER`, üres `search_path`-ú RPC-n keresztül. A claim `FOR UPDATE SKIP LOCKED` és időkorlátos lease használatával atomi. Lejárt lease újra claimelhető.

Feldolgozás:

1. `pending`/esedékes `retry` rekordok atomi claimje;
2. payload-verzió validálása;
3. text és HTML levél renderelése;
4. SMTP-küldés determinisztikus RFC Message-ID-val;
5. siker esetén `sent`, provider Message-ID és `sent_at` rögzítése;
6. hiba esetén append-only próbálkozásnapló és retry/dead-letter állapot.

Az `public.booking_email_delivery_attempts` napló minden próbálkozást külön, fizikailag nem törölhető rekordként őriz. Nem tárol SMTP-jelszót, teljes MIME levelet vagy nyers provider választ; csak biztonságos hibakódot, időtartamot, eredményt és korrelációt.

## 5. Retry és dead letter

Átmeneti hálózati hiba, timeout és SMTP 4xx válasz exponenciális visszalépéssel újrapróbálható. Kiinduló ütem: 1, 5, 15, 60, 240, 720 és 1440 perc; legfeljebb 8 próbálkozás.

SMTP hitelesítési/configurációs hiba, tartós 5xx címzetthiba vagy kimerített retry `dead_letter` állapotot eredményez. A rekord nem törlődik. Admin által indított kézi újrapróbálás külön, indoklással auditált művelet lehet.

Kötelező monitorjelek:

- legrégebbi esedékes pending/retry rekord kora;
- pending/retry/dead-letter darabszám;
- utolsó sikeres küldés ideje;
- worker utolsó sikeres futása;
- ismétlődő SMTP auth/config hiba.

Riasztás szükséges dead-letter rekordnál, elmaradt worker heartbeatnél és elfogadott küszöbnél régebbi esedékes értesítésnél.

## 6. SMTP és kézbesítési garancia

Elsődleges szolgáltatói irány a saját domaines MediaCenter.hu SMTP, provider adapteren keresztül. A Node workerhez verzióra rögzített Nodemailer használható. Kötelező környezeti paraméterek:

- `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`;
- `SMTP_USER`, `SMTP_PASS`;
- `BOOKING_EMAIL_FROM`, `BOOKING_EMAIL_REPLY_TO`;
- `CRON_SECRET`, Supabase szerveroldali kulcs;
- környezetenkénti `BOOKING_EMAIL_MODE=disabled|capture|send`.

A MediaCenter E-mail Admin 2026-09-03-i beállítási oldala alapján igazolt nem titkos paraméterek:

| Paraméter | Érték |
| --- | --- |
| `SMTP_HOST` | `pop3.mediacenter.hu` – a szolgáltató külön jelzi, hogy ez nem elírás |
| `SMTP_PORT` | `465` |
| `SMTP_SECURE` | `true` – közvetlen SSL/TLS |
| `SMTP_USER` | `foglalas@a-hely.com` – teljes e-mail cím |
| `BOOKING_EMAIL_FROM` | `A-Hely Foglalás <foglalas@a-hely.com>` |
| `BOOKING_EMAIL_REPLY_TO` | `foglalas@a-hely.com` |
| SMTP authentication | kötelező, a postafiók saját jelszavával |
| díjmentes limit | naponta 100 levél, levélenként legfeljebb 10 címzett |

A jelszó továbbra is kizárólag Vercel environment secret lehet. A booking értesítések mindig egy címzettnek mennek, ezért a 10 címzettes korlát nem probléma. A napi 100 levél viszont production kapacitási kockázat: a várt csúcsterhelés igazolása nélkül a díjmentes SMTP nem tekinthető végleges production megoldásnak. A MediaCenter szerint külön, bármely hálózatról egységesen használható privát SMTP hozzáférés vásárolható; ennek limitjeit és árát production döntés előtt be kell kérni.

Nyitva marad az SPF/DKIM/DMARC állapot és a bounce-kezelési lehetőség ellenőrzése.

SMTP mellett a DB-deduplikáció, lease és determinisztikus Message-ID megszünteti a normál párhuzamos/ismételt workerduplikációt. Marad azonban egy elosztott rendszeri rés: ha az SMTP szerver már átvette a levelet, de a worker a `sent` rögzítése előtt megszakad, a retry ritkán ismételt levelet okozhat. A foglalás és a kiküldési kötelezettség megőrzése érdekében nem jelölünk levelet elküldöttnek az SMTP-átadás előtt.

Ha üzletileg szigorú szolgáltatói idempotencia szükséges, API-alapú, idempotency key-t támogató providerre kell váltani. A provider adapter miatt ez nem igényel booking-RPC vagy outbox újratervezést.

## 7. Scheduler

Az ajánlott production ütemezés percenkénti, ismételhető workerhívás. A Vercel Hobby cron napi korlátozása miatt a percenkénti feldolgozás nem alapozható ellenőrzés nélkül Vercel Cronra.

Elsődleges terv:

- Supabase `pg_cron` percenként indít;
- `pg_net` meghívja a Vercel worker route-ot;
- az environment-specifikus URL és token Supabase Vaultban van, nem migrationben/repositoryban;
- a worker saját DB lease-e miatt a kihagyott vagy duplikált schedulerhívás biztonságos.

A staging audit idején csak a Vault extension volt bekapcsolva; `pg_cron` és `pg_net` engedélyezését külön migrációval és staging ellenőrzéssel kell elvégezni. Preview protection esetén külön, titkos bypass-konfiguráció vagy stabil staging URL szükséges.

## 8. Adatvédelem és jogosultság

- Mindkét új tábla RLS-e bekapcsolt és kliensoldalról deny-by-default.
- `anon` és `authenticated` nem kap közvetlen SELECT/INSERT/UPDATE/DELETE jogot.
- A booking RPC csak insertet végezhet; a worker kizárólag szűk claim/result RPC-ket használ.
- `SECURITY DEFINER` funkcióknál üres `search_path`, explicit qualification, `PUBLIC`/`anon`/`authenticated` execute revoke és kizárólag szükséges grant kötelező.
- Az esemény üzleti mezői és a próbálkozásnapló nem módosíthatók; fizikai törlés tiltott.
- Titok, nyers SMTP válasz és teljes e-mail tartalom nem kerül alkalmazáslogba vagy auditba.
- A végleges retention szabály külön jóváhagyásig nem törölhet kézbesítési adatot.

## 9. Legacy cutover

1. Az új tábla és RPC-módosítások először stagingre kerülnek, worker `capture` módban.
2. A már meglévő 135 staging `outbox_events` rekord érintetlen marad és nem kerül kiküldésre.
3. Cutover időpont és új `booking_email_outbox` kezdőazonosító auditáltan rögzül.
4. Csak cutover utáni, új e-mail outbox rekord dolgozható fel.
5. Production deploy előtt backup és rollback terv kötelező.
6. Production worker `disabled` módban nem claimel rekordot; a kiküldés csak teljes konfiguráció és explicit jóváhagyás után kerül `send` módba. Stagingben a `capture` mód külön `captured` eredményt használ, nem jelöl valódi kézbesítést.

## 10. Kötelező tesztek

### Adatbázis/pgTAP

- egyedi create/update/cancel pontosan egy megfelelő outbox rekord;
- adminművelet címzettje a booking owner, adminjelzés igaz;
- sorozat create és minden scope pontosan egy összefoglaló rekord;
- idempotens RPC retry nem duplikál;
- jogosulatlan vagy rollbackelt művelet nem hoz létre e-mail-feladatot;
- payload eseménykori adatot őriz későbbi booking/profile módosítás után is;
- RLS/grant, immutability és fizikai törlés tiltása;
- két konkurens claim ugyanazt a rekordot nem adja ki;
- lejárt lease visszavehető, élő lease nem;
- retry és dead-letter állapotátmenetek helyesek.

### Alkalmazás/Vitest

- minden payload-verzió validációja;
- magyar text és HTML sablonok create/update/cancel és sorozatváltozatai;
- HTML escape és hiányzó opcionális mezők;
- Europe/Budapest DST- és napváltási formázás;
- SMTP hibák biztonságos osztályozása;
- worker auth 401 titok nélkül;
- fake transporttal siker, retry, dead-letter és duplikált invocation.

### Staging UAT

- valós címre create/update/cancel;
- admin által végzett mindhárom művelet;
- sorozat create/following/series: műveletenként egy levél;
- provider átmeneti hiba és későbbi siker;
- hibás cím/dead-letter és riasztás;
- feladó, Reply-To, magyar ékezet, mobil/desktop e-mail kliens;
- outbox, próbálkozásnapló és audit egyeztetése.

## 11. Implementációs sorrend

1. adatbázis-migráció, claim/result RPC-k és pgTAP – **draft ágon elkészült, stagingre még nincs alkalmazva**;
2. booking RPC-k egyszeri/sorozatos enqueue módosítása és regressziótesztek – **draft ágon elkészült**;
3. provider adapter, fake transport és sablonok;
4. worker route, retry és alkalmazástesztek;
5. admin monitor/read model és riasztási heartbeat;
6. `capture` módú staging deploy és DB/e-mail reconciliation;
7. MediaCenter SMTP paraméterek + DNS hitelesítés;
8. valós staging UAT;
9. külön release review, backup/rollback ellenőrzés;
10. `main` merge és production `send` engedélyezés csak explicit tulajdonosi jóváhagyással.

### 2026-09-03-i implementációs checkpoint

Elkészült a `202609030001_booking_email_outbox.sql` migráció és a hozzá tartozó adatbázis-regressziós csomag:

- célzott outbox és append-only delivery-attempt tábla, RLS-sel és közvetlen kliens/service-role tábla-hozzáférés nélkül;
- idempotens belső enqueue helper deduplikációs ütközésvédelemmel;
- service-role-only, `FOR UPDATE SKIP LOCKED` + lejáró lease alapú claim RPC;
- lease-tokennel kerített sent/captured/retry/dead-letter eredményrögzítés;
- legfeljebb 8 befejezett próbálkozás, eseménykori payload-immutabilitás és fizikai törlés tiltása;
- 47 pgTAP ellenőrzés és külön két-workeres konkurencia-tesztscript.

A migráció nincs alkalmazva stagingre vagy productionre. A GitHub Database tests #520 friss adatbázis-resetből **685/685 pgTAP PASS** eredményt adott; az új két-workeres outbox claim konkurenciateszt, minden korábbi konkurenciateszt és a schema lint is PASS. Az Application checks #571, a helyi 91 unit teszt, typecheck, production build és a Vercel preview ellenőrzés szintén PASS.

A második, `202609030002_enqueue_booking_emails_from_audit.sql` migráció a kanonikus RPC-k korrelált auditjából, tranzakció végéig halasztott constraint triggerrel készíti az eseménykori e-mail snapshotot. A halasztás biztosítja, hogy a booking title és az admin Tréningterem-díjazás atomi mellékhatásai is lezáruljanak az enqueue előtt, miközben rollback esetén sem booking, sem e-mail-feladat nem marad. A trigger a sorozat auditját felismerve egyetlen `occurrence`/`following`/`series` összefoglalót készít, így a bookingonkénti legacy audit/outbox események nem okoznak e-mail duplikációt.

Az ehhez tartozó 29 új pgTAP ellenőrzéssel a teljes adatbáziscsomag **714/714 PASS** a GitHub Database tests #525 futásban. Az összes konkurenciateszt – beleértve az új integráció után izolált outbox claim race-t – és a schema lint PASS; Application checks #576 PASS. A két migráció továbbra sincs stagingre vagy productionre alkalmazva.

## 12. Nyitott külső függőségek

- MediaCenter privát SMTP limitjei és ára, ha a napi 100 levél nem ad megfelelő tartalékot;
- SPF/DKIM/DMARC és bounce-kezelés szolgáltatói ellenőrzése;
- SMTP at-least-once ritka duplikációs résének üzleti elfogadása, vagy idempotens API-provider választása;
- staging worker stabil elérési módja Vercel preview protection mellett;
- riasztási címzett/csatorna és időküszöbök.
