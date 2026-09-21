# Booking e-mail main-integráció — 2026-09-21

## Forrás és scope

- Base main: `eb91b00741ed9419c5f5de2223195b6927774935` (PR #173).
- Átvételi forrás: staging `c71f790e20e979898ac38f934ddb243747d008bc`.
- Célzott átvétel: booking-email modul és tesztek, belső worker route, admin e-mail monitor, eredeti három SQL-migráció és pgTAP teszt, konkurens claim teszt, nodemailer és típusfüggőség.
- Main naptárnavigáció, számlázási mezők, import, backup és health megőrzött. Csak új admin menüpont és email-monitor CSS kerül a meglévő UI mellé; mobil menü bezárása megmarad.
- A staging régi production-health cronjai nem kerülnek át. A worker percenkénti cronja külön végpontot hív, CRON_SECRET Bearer hitelesítéssel.
- Ez nem teljes staging merge; többügyfeles import külön feladat.

## Adatbázis

Az eredeti, stagingen már alkalmazott migrációk neve és tartalma megmarad:

1. `202609030001_booking_email_outbox.sql`
2. `202609030002_enqueue_booking_emails_from_audit.sql`
3. `20260903185410_booking_email_delivery_monitor.sql`

Ezek régebbi verziószámúak a jelenlegi main utolsó migrációinál. A production workflow `--include-all` előellenőrzése szükséges; kizárólag a fenti három várt migráció lehet újonnan pending. Eltérésnél vizsgálat szükséges, automatikus production db reset tilos. A PR CI üres helyi adatbázison reset/pgTAP/konkurencia/lint ellenőrzést végez. A már alkalmazott éles sémára való ráépítést a jóváhagyott deploy előtti dry-run és migration-list ellenőrzi.

A trigger csak új kanonikus audit INSERT eseményeket dolgoz fel, régi foglalásokat nem játszik vissza. A worker disabled módja nem tiltja az új outbox rekordok létrejöttét. Bekapcsolás előtt a felgyűlt sort és a címzési szándékot ellenőrizni kell. Import-események nem kanonikus booking események; az import nem lehet tömeges levélküldés mellékhatása.

## Konfiguráció és aktiválás

- `BOOKING_EMAIL_MODE`: alapérték `disabled`; `capture` levélküldés nélkül lezárja a feldolgozott tételeket; `send` valódi SMTP-küldés.
- `CRON_SECRET`: legalább 32 byte, titkos, egysoros. Környezetenként külön kezelendő.
- `BOOKING_EMAIL_FROM`, `BOOKING_EMAIL_REPLY_TO`, `BOOKING_EMAIL_MESSAGE_ID_DOMAIN`, `BOOKING_EMAIL_BATCH_SIZE`, `BOOKING_EMAIL_LEASE_SECONDS` a minta szerint.
- Send esetén `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS` szükséges; titok nem kerül Gitbe.
- A percenkénti Vercel cronhoz megfelelő csomag szükséges. A production projekt csomagját és schedulerét aktiválás előtt ellenőrizni kell; ez a PR nem módosít előfizetést.
- A send mód bekapcsolása és a production DB-változtatás külön jóváhagyás. Az integráció önmagában nem küld levelet.
- Vészleállítás: mode disabled és redeploy; a már futó küldést ez nem vonja vissza. Audit/outbox történet nem törölhető. SMTP-küldés és DB-nyugtázás nem közös tranzakció: összeomlás után ismételt kézbesítés lehetséges, a stabil Message-ID önmagában nem exactly-once garancia.

## Bizonyítékok

- Korábbi staging UAT és Resend kézbesítés: változatlan másolatok a `docs/evidence/2026-09-18-staging/` alatt; nem újratesztelendő üres sablonként.
- Integrált jelölt helyi ellenőrzése: pnpm install --frozen-lockfile sikeres; 28 fájl / 167 Vitest teszt PASS; typecheck PASS.
- Build, adatbázis CI és független review eredménye a PR-on rögzítendő; régi staging eredmény nem helyettesíti az integrációs CI-t.
- Production deployment/migráció/config és célzott kézbesítés ebben a munkában nem történt.
- `node scripts/check-release-evidence.mjs` konzisztenciaellenőrzés; `--release` a megmaradt kapuk miatt továbbra is blokkol.
