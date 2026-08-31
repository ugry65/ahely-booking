# Független review brief – Backup / restore / retention / monitoring

Dátum: 2026-08-31
Cél PR: #103 (`infra/100-backup-monitoring`)
Kapcsolódó issue-k: #100, #101, #102

## Review cél

Független második reviewer ellenőrizze, hogy a production adatbiztonsági megoldás nem tartalmaz-e olyan hibát vagy hiányt, amely adatvesztést, visszaállíthatatlanságot, hamis zöld monitoringot, secret-szivárgást vagy túl korai backup-törlést okozhat.

A review nem helyettesíti a későbbi valódi GDrive+B2 backup futást és izolált restore drillt.

## Elsődleges fájlok

- `docs/PRODUCTION_BACKUP_MONITORING_TECHNICAL_DESIGN.md`
- `docs/DECISION_2026-08-31_BACKUP_RETENTION_OBJECT_LOCK.md`
- `docs/BACKUP_RESTORE_RUNBOOK.md`
- `scripts/backup-production.sh`
- `scripts/test-backup-production.sh`
- `scripts/retention-production.py`
- `scripts/test-retention-production.sh`
- `.github/workflows/production-backup.yml`
- `.github/workflows/production-backup-retention.yml`
- `src/app/api/health/route.ts`
- a `system_health_check()` migráció és pgTAP tesztje

## Kötelező review kérdések

### A. Backup teljesség és konzisztencia
1. A Supabase CLI dumpok elegendők-e a `public`, `auth` és szükséges migrációs állapot visszaállításához?
2. Van-e olyan Supabase-managed adat vagy konfiguráció, amely nincs az artifactban és a runbook nem kezeli megfelelően?
3. Biztonságos-e a roles/schema/data/migration-history felosztás és a tervezett restore sorrend?
4. A backup artifact létrehozása valóban fail-closed-e minden részleges hiba esetén?
5. Ugyanaz a titkosított byte-sorozat kerül-e mindkét külső célra, és elég erős-e a remote integritásellenőrzés?

### B. Titkosítás és secret-kezelés
1. A napi runner csak `age` publikus recipient kulcsot igényel-e?
2. A recovery private key valóban távol tartható-e GitHubtól, GDrive-tól és B2-től?
3. Van-e esély connection string/OAuth/B2 secret logolására?
4. A GitHub Actions permission/environment/secret használat minimális és megfelelő-e?

### C. Retention / Object Lock
1. Helyes-e az elfogadott policy implementációja: 0–14 nap 4×/nap; 15–90 nap 1×/nap; 3–24 hónap 1×/hó?
2. Helyesen kezeli-e, hogy a B2 30 napos Governance lock miatt 0–30 nap között minden objektum megmarad?
3. Van-e timezone/DST/calendar-month határhiba a ritkításban?
4. Hiányzó vagy ismeretlen file/sidecar esetén valóban biztonságosan nem töröl-e?
5. Az `--apply` és scheduled workflow gate-ek elegendőek-e véletlen törlés ellen?
6. A 24 hónapos határ definíciója egyértelmű és helyes-e?

### D. Restore
1. Van-e veszély, hogy a runbook véletlenül productiont célozhat?
2. Elég erős-e a külső és belső checksum ellenőrzés?
3. A managed Supabase targettel való schema/auth ütközés kezelése megfelelően fail-closed-e?
4. A restore utáni acceptance lefedi-e a booking, permission, audit, pricing és settlement kritikus adatokat?
5. Milyen további automatizált kontrollszámot vagy restore-verification tesztet kell hozzáadni?

### E. Monitoring
1. A publikus `/api/health` nem ad-e ki érzékeny információt?
2. A DB health check valódi read-only DB művelet-e, és nem hoz-e létre üzleti adatot?
3. Előfordulhat-e hamis HTTP 200 / hamis `ok` állapot DB hiba esetén?
4. Megfelelő-e a négy külön backup heartbeat a 08/12/16/20 ütemezés miatt?
5. Az alert/recovery drill terve elég-e production gate-nek?

## Elvárt review eredmény

Findingok súlyossága:
- `BLOCKING`: production/merge előtt kötelező javítani;
- `MAJOR`: erősen javítandó, release döntés előtt rendezendő;
- `MINOR`: nem blokkoló minőség/üzemeltetési javítás;
- `INFO`: megjegyzés.

A review végén külön nyilatkozat szükséges:
- van-e BLOCKING finding;
- a backup/restore design alkalmas-e valódi sandbox restore drillre;
- a retention/Object Lock design alkalmas-e credential provisioning előtti továbblépésre;
- a monitoring alap alkalmas-e külső monitor bekötésére.

## Fontos gate

A review PASS sem jelent production GO-t. Utána még kötelező:
- valódi Google Drive + B2 backup;
- Object Lock konfiguráció bizonyítása;
- izolált restore drill;
- UptimeRobot alert/recovery drill;
- nyitott UAT blockerek lezárása;
- explicit production jóváhagyás.
