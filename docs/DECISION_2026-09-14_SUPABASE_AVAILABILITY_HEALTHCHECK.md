# Supabase production availability health-check

Dátum: 2026-09-14
Státusz: jóváhagyandó release-hardening változás

## Auditmegállapítás

A repository aktuális `main` állapotának auditja igazolta, hogy a production backup workflow és a négy Healthchecks.io heartbeat a mentési folyamatot figyeli, de külön, napi read-only Supabase availability/anti-pause health-check korábban nem volt implementálva.

A health-check és a backup két külön réteg:

- a backup adatmegőrzést és visszaállíthatóságot biztosít;
- a health-check az adatbázis elérhetőségét ellenőrzi és a Free plan pause-kockázatát csökkenti;
- a health-check nem ír üzleti adatot és nem helyettesíti a backupot.

## Implementált workflow

A `.github/workflows/supabase-availability-healthcheck.yml` minden nap 06:30-kor, Europe/Budapest szerint, valamint kézi indításkor fut.

A workflow kizárólag:

1. PostgreSQL klienst telepít;
2. ellenőrzi a dedikált kapcsolat-secret formátumát;
3. read-only `select 1;` lekérdezést futtat `PGCONNECT_TIMEOUT=15` értékkel.

Nem használja a backup DB-secretet, tárhely credentialt vagy a backup scriptet.

## Kötelező kézi production beállítás

A workflow merge-e önmagában nem tesz production secretet elérhetővé. A projektgazda vagy repository-admin állítsa be a GitHub `production` Environmentben:

```text
Name: SUPABASE_HEALTHCHECK_DB_URL
Type: Secret
Value: külön, read-only PostgreSQL connection URI a production Supabase projekthez
```

A már meglévő `SUPABASE_PRODUCTION_DB_URL` secretet nem szabad erre a célra újrahasználni, mert a health-checknek nem szükséges backup-jogosultság.

A kapcsolatnak lehetőleg külön, csak kapcsolódási és `SELECT` jogosultságú adatbázis-szereplőt kell használnia. A secret értéke nem kerülhet logba vagy repository-ba.

## Kötelező ellenőrzés merge után

A secret kézi beállítása és a workflow zöld merge-e után:

1. kézi workflow-dispatch;
2. a job sikerének ellenőrzése;
3. a következő napi 06:30-as futás PASS ellenőrzése;
4. sikertelen futás esetén GitHub-riasztás/incidenskezelés dokumentálása.

A production adatbázis, Auth, backup schedule és backup credential automatikusan nem módosítható.
