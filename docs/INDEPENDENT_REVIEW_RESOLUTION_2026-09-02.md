# Független backup/restore review – finding resolution

Dátum: 2026-09-02
Kapcsolódó: issue #104, PR #103
Review forrás: független Claude review, repository commit `141fa6a` állapotra.

## Cél

Ez a dokumentum a független review findingjainak hivatalos feldolgozási naplója. A findingokat nem automatikusan fogadjuk el: minden pontot összevetünk az aktuális repository állapottal és a 2026-09-01/02-i bizonyítékokkal.

## Finding státuszok

### B1 – PR még nincs `main` ágon

**Review severity:** BLOCKING  
**Resolution:** RELEASE GATE / nem implementációs hiba  
**Státusz:** NYITOTT A RELEASE-IG

A PR #103 szándékosan draft és nincs mergelve. A scheduled GitHub Actions workflow csak default branch-en válik aktívvá, ezért production automatikus backupot csak a végső review/UAT/gate után szabad aktiválni. Ez megfelel a projekt kötelező sorrendjének. `main` merge vagy production deploy továbbra sem történt.

Elfogadási feltétel: merge után az első valódi scheduled backup futás külön ellenőrzendő.

### B2 – PR-triggerelt workflow-k production secretekkel

**Review severity:** BLOCKING  
**Resolution:** ELFOGADVA ÉS JAVÍTVA  
**Státusz:** RESOLVED

A review helyesen azonosította, hogy ideiglenes proof workflow-k `pull_request` triggerrel production credentialökhöz fértek hozzá.

2026-09-02-i javítás:

- törölve: `.github/workflows/verify-production-dual-target-backup.yml`;
- törölve: `.github/workflows/verify-gdrive-oauth-client.yml`;
- törölve: `.github/workflows/verify-backup-heartbeat-alert.yml`;
- törölve: `.github/workflows/verify-backup-prerequisites.yml`;
- törölve: `.github/workflows/verify-gdrive-backup-target.yml`;
- `.github/workflows/configure-b2-object-lock.yml` átállítva kizárólag `workflow_dispatch` triggerre;
- a B2 konfiguráció futtatásához explicit `GOVERNANCE_30` confirmation input kötelező;
- nincs `pull_request` vagy schedule trigger a B2 admin workflow-ban.

A korábbi proof runok bizonyítékai a PR #103-ban és drill dokumentációban megmaradnak, de az ideiglenes workflow-k nem kerülnek production branch-re.

### B3 – Google OAuth rotáció dokumentációs ellentmondás

**Review severity:** BLOCKING  
**Resolution:** SECURITY FINDING LEZÁRVA; DOKUMENTÁCIÓ FOLYAMATOSAN KONSZOLIDÁLVA  
**Státusz:** SECURITY RESOLVED

A review a `141fa6a` állapotot vizsgálta. A review után a tényleges security gate lezárult:

1. a korábban screenshoton megjelent Google OAuth grant visszavonva;
2. `gdrive2:` újraengedélyezve az `A-Hely Backup` OAuth klienssel;
3. új rclone token generálva;
4. GitHub `BACKUP_GDRIVE_RCLONE_TOKEN` secret frissítve;
5. post-rotation Google Drive canary PASS;
6. post-rotation teljes dual-target production backup PASS;
7. bizonyító artifact: `ahely-booking-production_20260902T134133Z_6cfad69ed03c.tar.gz.age`;
8. végső log: `Backup artifact verified on both independent targets`.

A security kockázat tehát lezárt. Az aktuális PR- és restore-drill dokumentáció már PASS állapotként kezeli a rotációt. Régebbi történeti dokumentumokban szereplő korábbi blocker-szöveg csak történeti kontextusként értelmezhető.

### M1 – restore drill nem nulla üzleti adaton

**Review severity:** MAJOR  
**Resolution:** ELFOGADVA ÉS BIZONYÍTVA  
**Státusz:** RESOLVED

A 2026-09-01-i v2 production restore drill technikailag teljes PASS volt, de a production állapotban a legtöbb üzleti kontroll 0 volt. A review ezért helyesen kérte a nem nulla Auth/booking/audit/settlement adatok külön visszaállítási bizonyítását.

2026-09-02-án automatizált, izolált M1 regressziós drill készült:

- `scripts/fixtures/nonzero-restore-fixture.sql` reprezentatív nem nulla adatállapotot hoz létre;
- `scripts/test-backup-restore-nonzero.sh` a tényleges `scripts/backup-production.sh` backup-logikát futtatja;
- valódi `age` titkosítás/visszafejtés és SHA-256 ellenőrzés történik;
- a forrás stack leállítása után külön, pristine `supabase init` restore-target készül, alkalmazási migrációk előzetes ráfuttatása nélkül;
- a restore egy tranzakcióban, fail-closed módban fut;
- control-count, migration history, RLS, policy, FK és trigger ellenőrzés történik;
- a restored adatbázison schema lint fut.

Bizonyító futás:

- workflow: `Database tests`;
- run: `33647635924`;
- job: `100306833094`;
- `Run nonzero backup/restore sandbox drill`: PASS;
- teljes job: PASS;
- pgTAP: 50 fájl / 643 teszt PASS.

Forrás és restore pontosan egyező kontrollszámok:

- `auth_users=2`;
- `profiles=2`;
- `rooms=11`;
- `user_room_permissions=2`;
- `booking_series=1`;
- `bookings_total=13`;
- `bookings_active=12`;
- `bookings_cancelled=1`;
- `booking_cancellations=1`;
- `audit_logs=5`;
- `monthly_settlements=1`;
- `settlement_revisions=1`;
- `settlement_booking_lines=11`;
- `migration_history_rows=63`.

A migration history restore `COPY 63` eredménnyel futott. A szerkezeti RLS/policy/FK/trigger ellenőrzések PASS eredményt adtak.

Részletes bizonyíték: `docs/PRODUCTION_BACKUP_RESTORE_DRILL_PLAN_2026-09-01.md`.

**Következtetés:** az M1 production gate lezárva; a nem nulla üzleti adatok visszaállíthatósága automatizált regresszióval bizonyított.

### M2 – B2 napi kulcs túlzott jogosultsága

**Review severity:** MAJOR  
**Resolution:** ELFOGADVA ÉS IMPLEMENTÁLVA  
**Státusz:** IMPLEMENTÁCIÓ RESOLVED; POST-MERGE PROOF NYITOTT

A napi backup/retention korábban ugyanazt a B2 application key secretet használta, amely az Object Lock adminisztrációhoz is szükséges capability-ket hordozta. Least-privilege szempontból ezt szétválasztottuk.

2026-09-02-i javítás:

- létrejött külön bucket-restricted napi B2 application key: `ahely-booking-production-daily`;
- új GitHub secretek: `BACKUP_B2_DAILY_ACCOUNT_ID`, `BACKUP_B2_DAILY_APPLICATION_KEY`;
- `.github/workflows/production-backup.yml` kizárólag a `*_DAILY_*` credentialt használja;
- `.github/workflows/production-backup-retention.yml` kizárólag a `*_DAILY_*` credentialt használja;
- `.github/workflows/configure-b2-object-lock.yml` továbbra is a külön emelt jogú `BACKUP_B2_ACCOUNT_ID` / `BACKUP_B2_APPLICATION_KEY` párost használja;
- az emelt jogú Object Lock credential így nincs jelen a napi scheduled backup/retention workflow-kban.

Mivel a production backup workflow még nincs a default branch-en, a napi kulccsal végzett tényleges scheduled/dispatch proof csak merge után végezhető el biztonságosan. Elfogadási feltétel: az első post-merge production backup és retention dry-run a `*_DAILY_*` kulccsal sikeres legyen.

### M3 – retention és backup időzítési race

**Review severity:** MAJOR  
**Resolution:** ELFOGADVA ÉS JAVÍTVA  
**Státusz:** RESOLVED

2026-09-02-i javítás:

- retention schedule 21:30-ról 02:00 Europe/Budapest időpontra került;
- `production-backup.yml` és `production-backup-retention.yml` közös concurrency groupot használ: `production-backup-storage-maintenance`;
- `cancel-in-progress: false`;
- emiatt artifact létrehozás és retention törlés nem futhat párhuzamosan akkor sem, ha a GitHub scheduler késik.

### M4 – `cutoff_15` vs „0–14 nap”

**Review severity:** MAJOR  
**Resolution:** NEM HIBA / DOKUMENTÁCIÓS PONTOSÍTÁS  
**Státusz:** RESOLVED

A `cutoff_15 = now - 15 days` implementáció a 0–14 napos életkor-tartományt helyesen `<15 nap` intervallumként valósítja meg. Ez 15 darab életkor-napot jelent: 0,1,...,14.

A kód módosítása 14 napos cutoffra valójában túl korai ritkítást okozna.

### M5 – restore anti-production technikai guard

**Review severity:** MAJOR  
**Resolution:** RÉSZBEN ELFOGADVA  
**Státusz:** FELTÉTELES / JÖVŐBELI AUTOMATIZÁLÁSI GATE

Jelenleg nincs általános restore script, amely connection stringet fogadna és automatikusan restore-olna. A restore eljárás manuális, izolált local Supabase stackre dokumentált, és a runbook tiltja a production in-place restore-t.

Ezért jelen állapotban nincs olyan automation surface, amelybe host guard építhető. Döntés: ha restore script/automation készül, explicit target allowlist + production-deny guard + typed override nélkül nem kerülhet be.

### M6 – GitHub `production` Environment protection

**Review severity:** MAJOR  
**Resolution:** KÉZZEL ELLENŐRIZVE ÉS SZIGORÍTVA  
**Státusz:** RESOLVED

2026-09-02-án a GitHub `production` Environment beállításait a projektgazda képernyőképpel ellenőrizte, majd a branch-hozzáférést és bypass szabályt szigorította.

Aktuális állapot:

- Required reviewers: OFF;
- Wait timer: OFF;
- Deployment branches and tags: `Selected branches and tags`;
- engedélyezett branch: kizárólag `main`;
- administrator bypass: OFF;
- `SUPABASE_PRODUCTION_DB_URL` environment secretként tárolva.

Ez biztosítja, hogy a scheduled production backup/retention a `main` ágon ne akadjon manuális approvalra, ugyanakkor fejlesztési/PR branch ne férjen hozzá a production environmenthez.

## Egyéb findingok

- `/api/health` rate limit: MINOR; jelenlegi alacsony terhelés mellett nem release blocker, de monitorozandó.
- 24 hónapos retention calendar-month definíció: INFO; explicit dokumentációs pontosítás indokolt.
- restore runbook Windows/PowerShell-specifikus részei: INFO; a reprodukció jelenleg ezen a bizonyított platformon érvényes.
- restored schema lint: `public.create_booking` függvényben `v_existing_id` változó nem olvasott; nem M1/restore-integritási blocker, külön kódtisztításként kezelhető.

## Aktuális release állapot a review után

**NO production GO.**

A review technikai findingjai közül B2, B3 security része, M1, M3, M4 és M6 lezárva. M2 implementációja szintén lezárt; csak post-merge működési proof marad. M5 jövőbeli restore-automation gate.

Nyitott release/gate tételek:

1. B1: csak jóváhagyott merge után az első valódi scheduled production backup bizonyítása;
2. M2: csak jóváhagyott merge után daily B2 credentialdel production backup + retention dry-run proof;
3. mobil UAT #98;
4. teljes staging/UAT és végső production gate.

A fenti B1/M2 post-merge ellenőrzések **nem indokolják a merge előrehozását**: `main` merge és production aktiválás csak a mobil UAT, teljes staging/UAT és végső jóváhagyás után történhet.
