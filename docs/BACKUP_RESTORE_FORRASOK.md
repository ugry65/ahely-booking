# Backup/restore döntési források

Dátum: 2026-08-18

Ez a fájl a `BACKUP_RESTORE_STRATEGIA.md` időérzékeny külső feltételezéseinek ellenőrzési pontjait rögzíti. Az aktuális árakat és szolgáltatási feltételeket production bekapcsolás előtt újra ellenőrizni kell.

## Supabase hivatalos források

- Database Backups: https://supabase.com/docs/guides/platform/backups
- Pricing: https://supabase.com/pricing
- Backup and Restore using the CLI: https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
- Production Checklist: https://supabase.com/docs/guides/deployment/going-into-prod

## 2026-08-18-i ellenőrzött állapot

- Free: hivatalos automatikus database backup nincs a csomagban.
- Pro: induló listaár 25 USD/hó; napi backup, 7 nap retention.
- PITR: külön fizetős add-on, 7 napos retention hozzávetőleg 100 USD/hó; Small compute vagy nagyobb szükséges.
- A Supabase CLI támogatott logikai backup-folyamata külön role-, schema- és data-dumpot használ.
- A Supabase dokumentáció restore-hoz új/cél projekt használatát támogatja, és jelzi, hogy több nem adatbázisban tárolt beállítást külön kell helyreállítani.

A repository dokumentációja ne tekintse ezeket az árakat örök érvényűnek; csak a technikai döntés 2026-08-18-i indoklására szolgálnak.
