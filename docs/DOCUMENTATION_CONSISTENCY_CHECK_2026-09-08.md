# Dokumentációs konzisztencia-ellenőrzés – 2026-09-08

Cél: megakadályozni, hogy régi Supabase Pro/PITR feltételezések visszakerüljenek a projekt döntéseibe.

## Aktuális kötelező állítások

- Production Supabase: **Free plan**.
- Supabase Pro/PITR: **nem kötelező production feltétel**.
- Backup: saját, naponta négyszer futó logikai mentés.
- Külső célok: **Google Drive + Backblaze B2**.
- Dual-target integritás: tesztelt.
- Izolált restore-drill: 2026-09-01-én megtörtént.
- Supabase Free pause: availability/monitoring probléma, nem backup-probléma.
- Anti-pause: read-only DB health-check/monitoring külön operációs feladat.

## Ismerten elavult dokumentumrész

`TECHNIKAI_ARCHITEKTURA_ES_ADATMODELL.md` régi backup/PITR mondatai elavultak. Érvényes korrekció: `ARCHITECTURE_OVERRIDE_2026-09-08_FREE_BACKUP.md`.

## Kötelező AI/fejlesztő ellenőrzés

Supabase, backup, restore, availability vagy production-költség témájú döntés előtt ellenőrizni kell:

1. `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`;
2. `DECISION_2026-09-08_SUPABASE_FREE_AND_BACKUP_BASELINE.md`;
3. `BACKUP_RESTORE_STRATEGIA.md`;
4. `PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md`;
5. `ARCHITECTURE_OVERRIDE_2026-09-08_FREE_BACKUP.md`.

Ha régi dokumentumban Pro/PITR-kötelezettség jelenik meg, azt **nem szabad aktuális döntésként használni**.
