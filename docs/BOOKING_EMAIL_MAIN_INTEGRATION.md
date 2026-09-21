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
- Build PASS (worker és admin monitor dinamikus). Adatbázis CI és független review eredménye a PR-on rögzítendő; régi staging eredmény nem helyettesíti az integrációs CI-t.
- Production deployment/migráció/config és célzott kézbesítés ebben a munkában nem történt.
- `node scripts/check-release-evidence.mjs` konzisztenciaellenőrzés; `--release` a megmaradt kapuk miatt továbbra is blokkol.

## Integrációs regresszióvédelem

A CI külön helyi upgrade-próbát futtat: a három e-mail migráció nélkül újraépíti a main sémát, utólag alkalmazza a három eredeti SQL-t, majd ismét futtatja a pgTAP teszteket. Ez az alkalmazási sorrendet vizsgálja, nem a production adatok másolata. Az ügyfélimport-teszt külön ellenőrzi, hogy import és próbaimport-visszavonás után sem keletkezik outbox értesítés.

## Rögzített integrációs CI

Vizsgált kód: `13744ace01e89f65177e187ba2ce1827fb8f3721`.

- [Application checks #749](https://github.com/ugry65/ahely-booking/actions/runs/35581838051): PASS (167 alkalmazásteszt, typecheck, build, meglévő backup/health guardok).
- [Database tests #588](https://github.com/ugry65/ahely-booking/actions/runs/35581838111): pgTAP PASS, minden konkurenciateszt PASS, late main upgrade PASS. A pgTAP friss sémán és main-upgrade után is sikeres.
- [Release evidence #5](https://github.com/ugry65/ahely-booking/actions/runs/35581837995): PASS.
- A DB lint átment; a változatlan create_booking függvényben egy nem olvasott v_existing_id változó figyelmeztetése megmaradt.
- A fenti kódot követő lezáró változás csak e bizonyítékokat rögzíti és a meglévő test-database.sh eredeti futtatási jogosultságát őrzi meg. A végleges HEAD CI-je a PR #174 ellenőrzései között található.
- Független kritikus SQL/security review még szükséges az AGENTS.md alapján. Merge / éles migráció / send aktiválás nem történt.
