# Supabase Free és backup/restore költségbaseline

Dátum: 2026-09-08
Státusz: **kötelező, aktuális üzleti és technikai döntés**

Az A-Hely production Supabase környezete Free planon készül és üzemel. A Supabase Pro/PITR nem production előfeltétel és nem kötelező release-gate.

A jóváhagyott modell:

- automatikus PostgreSQL logikai backup naponta négyszer, 08:00, 12:00, 16:00 és 20:00 Europe/Budapest szerint;
- két független off-site cél: Google Drive és Backblaze B2;
- titkosítás, manifest, checksum és feltöltés utáni read-back;
- többgenerációs retention és B2 Object Lock;
- dokumentált restore-folyamat és izolált restore drill.

A dual-target integritás és a restore-folyamat már bizonyított. A trigger-, credential-, monitoring- és aktiválási kontrollok release-hardening tételek, nem új architekturális döntések.

A Free plan automatikus pause kockázata külön availability probléma. Ezt rendszeres, biztonságos, read-only health-check kezeli; a health-check nem módosíthat üzleti adatot és nem helyettesíti a backupot.

Superseded minden korábbi állítás, amely a production indulását Supabase Pro, menedzselt backup vagy PITR meglétéhez köti.
