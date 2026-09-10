# Booking e-mail staging capture runbook

## Cél és biztonsági korlát

Ez a runbook a `feature/107-booking-email-outbox` ág staging ellenőrzését írja le valódi e-mail-küldés nélkül. A kötelező üzemmód `BOOKING_EMAIL_MODE=capture`: a worker rendereli és auditáltan lezárja az értesítést, de nem nyit SMTP-kapcsolatot.

Tilos ebben a folyamatban:

- production adatbázist, production Vercel environmentet vagy `main` ágat módosítani;
- `BOOKING_EMAIL_MODE=send` értéket használni;
- SMTP-jelszót repositoryba, issue-ba, PR-ba, logba vagy chatbe írni;
- a 135 régi `public.outbox_events` rekordot módosítani vagy feldolgozni;
- staging migrációt backup/checkpoint, dry-run és külön deploy-döntés nélkül alkalmazni.

## 2026-09-04-i olvasási audit

| Ellenőrzés | Eredmény |
| --- | --- |
| Supabase projekt | `ahely-booking-staging` (`fvwapntzhavhgazeflri`), `ACTIVE_HEALTHY`, `eu-west-2` |
| Legutolsó remote migráció | `20260829145720_allow_past_booking_creation` |
| Régi `public.outbox_events` | 135 rekord, megőrzendő |
| Új `public.booking_email_outbox` | még nincs telepítve |
| Új `public.booking_email_worker_runs` | még nincs telepítve |
| Supabase Vault | engedélyezve |
| `pg_cron` / `pg_net` | nincs engedélyezve |

A repository alapján a következő migrációk függők:

1. `20260830183000_booking_update_cutoff_guard.sql`
2. `202609030001_booking_email_outbox.sql`
3. `202609030002_enqueue_booking_emails_from_audit.sql`
4. `20260903185410_booking_email_delivery_monitor.sql`

Ez nem helyettesíti a GitHub Actions `dry-run` kimenetét. Eltérés esetén meg kell állni, és előbb a migration history driftet kell tisztázni.

## 1. Kötelező előfeltételek

- A PR aktuális commitján az Application checks, Database tests és Vercel preview PASS.
- A staging adatbázisról van visszaállítható checkpoint/backup.
- A `.github/workflows/staging-database-deploy.yml` `dry-run` futása pontosan a fenti négy migrációt mutatja függőként.
- A staging Vercel deployment kizárólag a staging Supabase projekthez kapcsolódik.
- A worker URL stabil és Vercel Deployment Protection mellett is csak a tervezett titkosított útvonalon érhető el.
- A tesztelő admin és booking owner e-mail-címe staging tesztadat; production címzett nem használható.

## 2. Vercel Preview környezeti szerződés

Az értékeket a `feature/107-booking-email-outbox` ágra szűkített Preview environmentben kell tartani. Production scope-ba ebben a szakaszban semmi nem kerülhet.

| Változó | Capture érték / szabály |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | a staging Supabase API URL-je |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | kizárólag staging publishable/anon kulcs |
| `SUPABASE_SERVICE_ROLE_KEY` | kizárólag staging service-role secret, szerveroldali |
| `SITE_URL` | a stabil staging/preview URL |
| `BOOKING_EMAIL_MODE` | kötelezően `capture` |
| `BOOKING_EMAIL_BATCH_SIZE` | kezdetben `10` |
| `BOOKING_EMAIL_LEASE_SECONDS` | kezdetben `300` |
| `BOOKING_EMAIL_FROM` | `A-Hely Foglalás <foglalas@a-hely.com>` |
| `BOOKING_EMAIL_REPLY_TO` | `foglalas@a-hely.com` |
| `BOOKING_EMAIL_MESSAGE_ID_DOMAIN` | `a-hely.com` |
| `CRON_SECRET` | legalább 32 bájtos, egysoros, környezetenként egyedi secret |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS` | capture módban nem szükségesek; `SMTP_PASS` ne legyen beállítva ehhez a próbához |

A secret változók neve sem kaphat `NEXT_PUBLIC_` előtagot. Környezeti változó módosítása után új Preview deployment szükséges; régi deployment nem veszi át visszamenőleg az új értéket.

## 3. Staging adatbázis kapu

1. Rögzíteni kell az aktuális migration historyt, a kritikus táblák létezését és a régi `outbox_events` darabszámát.
2. Le kell futtatni a `Staging database deploy` workflow-t `dry-run` módban.
3. Csak külön staging deploy-döntés után futhat ugyanaz a workflow `deploy` módban.
4. Deploy után a local/remote migration historynak egyeznie kell.
5. Ellenőrizni kell:
   - mindhárom booking-email tábla RLS-e aktív;
   - `anon` és `authenticated` nem kap közvetlen tábla-hozzáférést;
   - claim/complete és worker-run RPC csak `service_role` számára futtatható;
   - a régi `outbox_events` darabszáma változatlan;
   - a Supabase Security Advisor nem jelez új, a változáshoz köthető hibát.

`pg_cron` és `pg_net` engedélyezése, Vault secret létrehozása és aktív perces job beállítása külön scheduler-migráció/fázis. Az első capture UAT-hoz elegendő egy védett, egyszeri workerhívás; így a scheduler nem tud váratlanul ismételten futni.

## 4. Alapállapot és cutover-jelölés

A migráció után, de az első tesztfoglalás előtt rögzíteni kell:

- UTC cutover időpont;
- az új `booking_email_outbox` legnagyobb azonosítója, illetve üres tábla esetén ennek ténye;
- az új outbox státusz szerinti darabszámai;
- a régi `outbox_events` darabszáma;
- a worker-run tábla kezdőállapota.

Csak a cutover után keletkezett új booking-email rekordok vehetők figyelembe. A snapshot nem tartalmazhat címzettet, e-mail címet, payloadot vagy levéltartalmat.

## 5. Capture UAT sorrend

Minden sor után előbb az audit/outbox egyezést kell ellenőrizni, és csak utána jöhet a következő művelet.

1. Egyedi foglalás létrehozása saját tulajdonossal.
2. Ugyanennek a foglalásnak a módosítása.
3. Ugyanennek a foglalásnak a törlése/lemondása.
4. Admin által végzett létrehozás, módosítás és lemondás másik booking owner részére.
5. Ismétlődő sorozat létrehozása: egy összefoglaló rekord.
6. Egy előfordulás, az adott és következő alkalmak, majd teljes sorozat módosítása/lemondása: logikai műveletenként egy rekord.
7. Minden tesztcsoport után a védett worker route egyszeri `POST` meghívása ugyanazzal a Preview-scope `CRON_SECRET` értékkel, vagy a staging admin `/admin/email-ertesitesek` oldalán a capture-only indítógomb használata. Az admin indítás szerveroldalon újra ellenőrzi az aktív admin jogosultságot és a `capture` módot; `send` vagy `disabled` módban fail-closed módon megtagadja a futást.
8. Az admin `/admin/email-ertesitesek` nézet ellenőrzése címzett- és tartalomszivárgás nélkül.

Elvárt állapot:

- minden sikeres logikai booking művelethez pontosan egy új outbox rekord tartozik;
- a címzett a booking owner, adminműveletnél is;
- a worker `captured` állapotot rögzít, `sent` értéket nem;
- delivery attempt és worker-run audit darabszámai egyeznek az outbox változásokkal;
- nincs SMTP-kapcsolat és nincs valódi levél;
- a 135 legacy outbox rekord és a pénzügyi/foglalási adatok változatlanul megmaradnak.

## 6. Azonnali megállási feltételek

A tesztet le kell állítani, a workert `disabled` módra kell visszaállítani, és nem szabad újra futtatni, ha:

- a dry-run a várttól eltérő migrációt vagy driftet mutat;
- bármely környezeti változó production Supabase projektre mutat;
- a worker válasza nem `capture`, vagy `sent_count` nagyobb nullánál;
- egy logikai booking művelethez nulla vagy egynél több outbox rekord keletkezik;
- jogosulatlan kérés nem 401-et kap;
- címzett, payload, levéltörzs, SMTP-válasz vagy secret megjelenik admin nézetben/logban;
- a legacy outbox darabszáma, foglalási adatok vagy pénzügyi adatok váratlanul változnak;
- stale lease, dead letter, befejezetlen worker-run vagy nem magyarázott retry marad.

## 7. Visszaállás

1. A branch-scope Preview environmentben `BOOKING_EMAIL_MODE=disabled`.
2. Új Preview deployment, majd autorizált workerhívás: 200 és nulla claim/küldés.
3. Scheduler létrehozása esetén a jobot inaktiválni kell; az első UAT-ban scheduler eleve nem készül.
4. A booking-email audit- és outbox rekordokat nem töröljük. A hibás teszt eredményét megőrizzük és külön jegyzőkönyvben indokoljuk.
5. Séma-visszaállítás csak bizonyított adatvesztési/súlyos működési hiba esetén, a checkpoint és külön jóváhagyás alapján történhet.

## 8. Következő külön kapuk

Capture PASS után is külön döntés marad:

- `pg_cron` + `pg_net` scheduler implementálása és staging aktiválása;
- MediaCenter SMTP-jelszó kizárólag Vercel secretként történő beállítása;
- SPF, DKIM, DMARC és bounce-kezelés ellenőrzése;
- napi 100 levél kapacitás megfelelősége vagy privát SMTP csomag;
- valós SMTP UAT kontrollált címzettel;
- production backup, migráció és `send` aktiválás.

Egyik kapu sem jelent automatikus `main` merge-et vagy production deployt.

## 9. Publikus DNS audit – 2026-09-04

Az olvasási audit eredménye:

- az `a-hely.com` MX rekordjai a MediaCenter `posta.mediacenter.hu`–`posta5.mediacenter.hu` kiszolgálóira mutatnak;
- egyetlen, szintaktikailag érvényes SPF rekord van, amely az MX-eket és MediaCenter IP-tartományokat engedélyezi, `~all` softfail lezárással;
- az SPF rekord `ptr` mechanizmust is használ, amely elavult/nem ajánlott; ennek cseréjét a MediaCenterrel kell egyeztetni, nem önállóan átírni;
- `_dmarc.a-hely.com` alatt nem található DMARC rekord;
- a `default._domainkey.a-hely.com` DKIM selector alatt nem található rekord, de ez önmagában nem bizonyítja a DKIM hiányát, mert a szolgáltató más selectort használhat.

A valós SMTP UAT előtt a MediaCentertől meg kell erősíteni a DKIM selectort és a javasolt DMARC/SPF beállítást. Alternatív bizonyíték egy kontrollált próbaüzenet teljes hitelesítési fejléce (`Authentication-Results`, `DKIM-Signature`) úgy, hogy abban címzett vagy egyéb személyes adat ne kerüljön repositoryba/chatbe.

## 10. Staging adatbázis-deploy checkpoint – 2026-09-04

A projektgazda kifejezett staging-jóváhagyása, a sikeres dry-run #13, valamint a promóciós commit zöld Application CI, Database CI és Vercel ellenőrzése után az automatikus staging workflow #14 alkalmazta:

- `20260830183000_booking_update_cutoff_guard.sql`;
- `202609030001_booking_email_outbox.sql`;
- `202609030002_enqueue_booking_emails_from_audit.sql`;
- `20260903185410_booking_email_delivery_monitor.sql`.

A workflow local/remote migration history egyezést és „Remote database is up to date” utó-dry-runt adott. A megismételt automatikus futás #15 no-opként szintén PASS lett. A közvetlen read-only ellenőrzés szerint az új outbox, delivery-attempt és worker-run táblák léteznek, üresek, az `authenticated` szerepkörnek nincs rajtuk közvetlen tábla-hozzáférése, a szükséges service-role worker execute jogok megvannak.

Ez csak a staging séma telepítését zárja le. A runtime `disabled`; scheduler, runtime secret, capture UAT és valós SMTP UAT nem történt. Main merge és production deploy nem történt.

## 11. Capture UAT eredmény – 2026-09-04

A pontos branch-scope Preview runtime `BOOKING_EMAIL_MODE=capture` módban, SMTP-változók nélkül elkészült. A kézi secret-mozgatást kiváltó admin-only capture indító `bc68e22` commitján Application checks #591, Database tests #540 és Vercel Preview PASS.

A teljes UAT eredménye:

- egyedi create/update/cancel: PASS;
- admin által más booking owner részére végzett create/update/cancel: PASS; a recipient minden esetben a booking owner, nem az admin actor;
- teljes sorozat create/update/cancel: műveletenként egy `series` összefoglaló rekord, PASS;
- egyetlen előfordulás update/cancel: műveletenként egy `occurrence` rekord, PASS;
- „ezt és a következő alkalmakat” update/cancel: műveletenként egy `following` rekord, PASS;
- összesen 16 outbox rekord és 16 append-only delivery attempt, mind `captured`;
- `sent=0`, retry=0, dead-letter=0, provider Message-ID=0, pending/stale=0;
- egy külön üres workerfutás `success`, `claimed=0`, `captured=0` eredményt és nulla új delivery attemptet adott: idempotens no-op PASS.

A 135 UAT előtti legacy `outbox_events` rekord sértetlen maradt; az UAT során végzett booking műveletek elvárt új kanonikus legacy audit-eseményeket hoztak létre. SMTP-kapcsolat és valós e-mail-küldés nem történt. A capture kapu lezárult; a 8. fejezetben felsorolt scheduler-, DNS/hitelesítési és valós SMTP-kapuk külön jóváhagyást igényelnek. Main merge és production deploy nem történt.
