# Anti-pause UAT checklist

- [ ] Preview/staging route helyes Bearer tokennel 200-at ad.
- [ ] Token nélkül 401.
- [ ] A válasz csak `ok` állapotot tartalmaz, rekordadatot nem.
- [ ] A DB lekérdezés read-only.
- [ ] `pnpm test` sikeres.
- [ ] `pnpm typecheck` sikeres.
- [ ] Production `CRON_SECRET` megléte ellenőrizve, értéke nem kerül dokumentációba.
- [ ] Production deploy explicit tulajdonosi jóváhagyással történt.
- [ ] Vercel Cronban 4 napi futás látható.
- [ ] Első cron futás 200.
- [ ] Supabase activity megjelenik.
- [ ] 8 nap után nincs automatikus pause.
