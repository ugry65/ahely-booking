# Architektúra-korrekció – Supabase Free, backup és availability

Dátum: 2026-09-08
Státusz: **azonnal alkalmazandó override**

Ez a dokumentum a `TECHNIKAI_ARCHITEKTURA_ES_ADATMODELL.md` backup/PITR részeinek korrekciója. Az adatmodell, foglalási motor, RLS, audit és egyéb architekturális részek változatlanok.

## Felülírt régi állítások

A következő régi architekturális állítások nem érvényesek többé:

- `PITR + elkülönített backup` mint kötelező production komponens;
- production minimumként menedzselt DB backup + 7 napos PITR;
- legfeljebb 15 perces RPO PITR-rel mint kötelező induló cél;
- az a mondat, hogy a fizetős PITR production előtt kötelező;
- a production PITR költségkerete mint nyitott üzleti döntés.

## Aktuális architektúra

Production adatbázis: **Supabase Free PostgreSQL**.

Adatvédelmi/restore réteg:

`Supabase Free PostgreSQL -> naponta 4x logikai backup -> titkosítás + checksum -> Google Drive + Backblaze B2 -> retention/Object Lock -> restore runbook/drill`

Availability/anti-pause réteg:

`külső monitor -> biztonságos health endpoint -> read-only Supabase/PostgreSQL ellenőrzés -> alert/recovery`

A két réteg külön problémaosztályt kezel:

- backup/restore = adatvesztés és helyreállíthatóság;
- health/monitoring = elérhetőség, lassulás, Supabase Free pause kockázat.

## Kötelező hivatkozások

Részletes aktuális források:

1. `DECISION_2026-09-08_SUPABASE_FREE_AND_BACKUP_BASELINE.md`;
2. `BACKUP_RESTORE_STRATEGIA.md` v2.0;
3. `PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md` §3 és §5;
4. aktuális production backup/restore runbook és implementációs bizonyítékok.

Ezek precedenciát élveznek a 2026-08-16-i architektúradokumentum elavult PITR/Pro mondataival szemben.
