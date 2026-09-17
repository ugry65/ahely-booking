# Production go-live readiness – 2026-09-10

## Kiinduló állapot

A production AllBooked migráció közvetlen adatbázis-ellenőrzéssel lezárult és reconciliált:

- 1 importált felhasználó;
- 21 aktív foglalás;
- 21 migration-ledger sor;
- 21 import audit rekord;
- 19 × 60 perc + 2 × 90 perc;
- összesen 1320 perc / 22 óra;
- Forrás tér hozzáférés;
- nincs legacy ár override, settlement, settlement line vagy payment maradvány;
- duplikáció vagy részleges import nincs.

Az importot nem szabad újraindítani.

## Még nyitott production blocker-ek

### 1. Booking e-mail / transactional outbox

Issue: #107, PR: #111.

A #111 továbbra is draft, nincs mainbe merge-elve, és a PR jelenlegi transport-szerződése MediaCenter SMTP-re épül. Közben az auth e-mailhez a Resend stagingen igazoltan működik. Production GO előtt a booking e-mail worker tényleges transportját, schedulerét, retry-ját és valós create/update/cancel/admin/sorozat UAT-ját véglegesíteni kell.

### 2. Safe public health endpoint + külső monitoring

Issue: #102, PR: #146.

A #146 biztonságos, DB-backed `/api/health` endpointot készít elő. Production GO-hoz azonban az endpoint önmagában nem elég: UptimeRobot (vagy ekvivalens) availability monitor, kontrollált alert/recovery drill és backup heartbeat monitor is szükséges.

### 3. 4× napi production backup automatizmus

Issue: #101, umbrella #100.

A main jelenleg production backup/restore drill workflow-kat tartalmaz, de a normál 08:00 / 12:00 / 16:00 / 20:00 Europe/Budapest ütemezett production backup workflow nincs még mainen. Production GO előtt a már bizonyított titkosított Drive+B2 backup mechanizmust tényleges, rendszeres ütemezésben is aktiválni és heartbeat monitorral felügyelni kell.

### 4. Supabase Free anti-pause

PR #120 elkészült és merge-elt, de a base-je a `feature/107-booking-email-outbox`, nem `main`. Emiatt az anti-pause endpoint/cron jelenleg nem tekinthető production-main részének. Production GO előtt ezt tisztán main-alapú release-szeletként kell kezelni, CI/UAT után explicit jóváhagyással.

### 5. Production smoke/UAT

A productionon a migráció után teljes funkcionális smoke szükséges legalább:

- login/logout;
- admin hozzáférés;
- foglalási naptár betöltés;
- meglévő migrált foglalások megjelenése;
- jogosultságok;
- normál foglalás létrehozás/módosítás/lemondás tesztuserrel;
- ismétlődő foglalás alapfolyam;
- havi órák/admin riport alapellenőrzés;
- e-mail értesítések, amikor a #107 production-ready.

## Nem blocker, de javítandó

Issue #126: a foglalási naptár napváltásakor a navigációs gomb `Folyamatban…` állapotban maradhat. Ez UI-regresszió; production release előtt javítandó és regressziós teszt szükséges.

## Javasolt sorrend

1. #146 health endpoint CI/review lezárása, de main merge csak explicit production jóváhagyással.
2. #107/#111 aktualizálása a tényleges SMTP szolgáltatóra és teljes staging valós e-mail UAT.
3. #101 normál 4× napi backup schedule + heartbeat.
4. #120 anti-pause main release-szelet.
5. #126 UI-regresszió javítása.
6. teljes production smoke/UAT.
7. #100/#101/#102/#107 dokumentált lezárása és végső GO döntés.

Production változtatás csak explicit tulajdonosi jóváhagyással történhet.
