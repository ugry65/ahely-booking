# Booking e-mail – Resend staging UAT státusz

Dátum: 2026-09-10

A projektgazda megerősítése alapján a szükséges staging Vercel környezeti változók elkészültek `Preview / staging` scope-pal, beleértve a Resend SMTP-konfigurációt, `CRON_SECRET`-et és a staging `SUPABASE_SERVICE_ROLE_KEY`-t.

Következő kapu: friss staging deployment az új environment variable-k felvételével, majd valós e-mail UAT a `docs/BOOKING_EMAIL_RESEND_STAGING_UAT.md` szerint.

Production booking e-mail küldés továbbra sincs engedélyezve.
