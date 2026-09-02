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
**Resolution:** STALE FINDING + DOKUMENTÁCIÓS KONSZOLIDÁCIÓ SZÜKSÉGES
**Státusz:** SECURITY RÉSZ RESOLVED; DOC NORMALIZATION NYITOTT

A review a `141fa6a` állapotot vizsgálta. A review után a tényleges security gate lezárult:

1. a korábban screenshoton megjelent Google OAuth grant visszavonva;
2. `gdrive2:` újraengedélyezve az `A-Hely Backup` OAuth klienssel;
3. új rclone token generálva;
4. GitHub `BACKUP_GDRIVE_RCLONE_TOKEN` secret frissítve;
5. post-rotation Google Drive canary PASS;
6. post-rotation teljes dual-target production backup PASS;
7. bizonyító artifact: `ahely-booking-production_20260902T134133Z_6cfad69ed03c.tar.gz.age`;
8. végső log: `Backup artifact verified on both independent targets`.

A security kockázat tehát lezárt. A runbook/technical design régi „open blocker” szövegét a dokumentációs normalizációban frissíteni kell.

### M1 – restore drill nem nulla üzleti adaton

**Review severity:** MAJOR
**Resolution:** ELFOGADVA
**Státusz:** NYITOTT RELEASE GATE

A 2026-09-01-i v2 restore drill technikailag teljes PASS, de a production állapotban a legtöbb üzleti kontroll 0 volt. Emiatt a nem nulla Auth/booking/audit/settlement adatok visszaállítása még nincs teljes körűen bizonyítva.

Döntés: production GO előtt kötelező egy új izolált staging/sandbox restore drill nem nulla reprezentatív adatokkal. Nem elég „később javasolt” feladatként kezelni.

Minimum bizonyítandó:

- legalább 1 auth user + profile;
- room permission;
- booking + booking series/releváns ismétlődés;
- cancellation/audit sor;
- monthly settlement + revision + booking line;
- RLS és FK/trigger működés restore után;
- control-count egyezés.

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

A kód módosítása 14 napos cutoffra valójában túl korai ritkítást okozna. Dokumentációban érdemes explicit `<15 nap` megfogalmazást használni.

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

Ez biztosítja, hogy a scheduled production backup/retention a `main` ágon ne akadjon manuális approvalra, ugyanakkor fejlesztési/PR branch ne férjen hozzá a production environmenthez. A one-shot/admin workflow-k sem használhatják a production environmentet fejlesztési branchről.

## Egyéb findingok

- `/api/health` rate limit: MINOR; jelenlegi alacsony terhelés mellett nem release blocker, de monitorozandó.
- 24 hónapos retention calendar-month definíció: INFO; explicit dokumentációs pontosítás indokolt.
- restore runbook Windows/PowerShell-specifikus részei: INFO; a reprodukció jelenleg ezen a bizonyított platformon érvényes.

## Aktuális release állapot a review után

**NO production GO.**

Nyitott kritikus/major gate-ek:

1. B1: merge után tényleges scheduled backup bizonyítás;
2. M1: nem nulla reprezentatív adattal új restore drill;
3. M2: post-merge daily B2 credential backup + retention dry-run bizonyítás;
4. mobil UAT #98;
5. teljes staging/UAT és végső production gate.

A B2 PR-trigger security finding (B2), OAuth security finding (B3 security része), retention race (M3), B2 least-privilege implementáció (M2) és GitHub production Environment protection finding (M6) 2026-09-02-án javítva/lezárva; M2-nél csak a post-merge működési proof marad.