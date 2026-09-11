# Architektúra-korrekció – Supabase Free, backup és availability

Dátum: 2026-09-08
Státusz: **azonnal alkalmazandó override**

Ez a dokumentum kizárólag a régi kötelező Pro/PITR állításokat írja felül. Az adatmodell, foglalási motor, RLS, audit és egyéb architekturális döntések változatlanok.

Aktuális adatvédelmi réteg:

`Supabase Free PostgreSQL -> naponta 4x logikai backup -> titkosítás + checksum -> Google Drive + Backblaze B2 -> retention/Object Lock -> restore runbook/drill`

Aktuális availability réteg:

`külső monitor -> biztonságos health endpoint -> read-only PostgreSQL ellenőrzés -> alert/recovery`

A backup/restore adatvesztést és helyreállíthatóságot kezel. A health/monitoring az elérhetőséget és a Free plan pause kockázatát kezeli. Egyik sem helyettesíti a másikat.

Részletes aktuális források:

1. `DECISION_2026-09-08_SUPABASE_FREE_AND_BACKUP_BASELINE.md`;
2. `BACKUP_RESTORE_STRATEGIA.md` v2.0;
3. az aktuális production backup/restore implementáció és release-readiness jegyzőkönyv.
