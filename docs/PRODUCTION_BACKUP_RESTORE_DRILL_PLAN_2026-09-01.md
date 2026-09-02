# A-Hely – Production backup restore drill terv és jegyzőkönyv

Dátum: 2026-09-01
Utolsó dokumentációs frissítés: 2026-09-02
Státusz: **TELJES PASS – backupVersion 2 end-to-end restore drill és reprezentatív nem nulla adatos regressziós restore is sikeres.**

## Reprodukciós forrás

A teljes, parancsszintű, reprodukálható eljárás külön operatív runbookban található:

`docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md`

A jelen dokumentum a tényleges 2026-09-01-i production backup/restore bizonyító drill, valamint a 2026-09-02-i reprezentatív nem nulla adatos automatizált restore-regresszió jegyzőkönyve. A runbook különválasztja a normál jövőbeli restore-folyamatot azoktól az egyszeri diagnosztikai kerülőutaktól, amelyek a v1 hiba feltárásához kellettek.

## Cél

Bizonyítani, hogy a production adatbázisról készült, client-side `age` titkosítású mentés ténylegesen visszaállítható úgy, hogy production és staging adat ne kerüljön veszélybe.

A 2026-09-02-i kiegészítő M1 regressziós drill célja ezen felül annak bizonyítása volt, hogy a backup/restore folyamat nemcsak üres üzleti táblákkal működik, hanem reprezentatív, nem nulla Auth-, jogosultság-, ismétlődő foglalás-, lemondás-, audit- és havi elszámolási adatokkal is.

## Biztonsági alapelv

A restore drill kizárólag izolált PostgreSQL 17 / local Supabase környezetben történt. Production vagy staging adatbázisra a drill nem futott.

A recovery private key nem került GitHubba, Google Drive-ra vagy Backblaze B2-re. A 2026-09-01-i production artifact visszafejtése azon a helyi gépen történt, ahol a recovery key biztonságosan rendelkezésre állt. A 2026-09-02-i automatizált regresszió külön, futásonként generált tesztkulcsot használt, amely kizárólag az izolált CI sandboxban létezett.

## Bizonyított helyi restore környezet

A 2026-09-01-i sikeres production restore drill során használt környezet:

- Docker CLI: `29.7.2`;
- Docker Desktop + WSL2;
- Node: `v24.18.0`;
- Supabase CLI: `2.116.0` (`npx.cmd supabase`);
- local Supabase PostgreSQL image: `ghcr.io/supabase/postgres:17.6.1.165`;
- rclone: `1.75.0`;
- age: `1.3.1`.

Ezek nem örök verziópin-ek, hanem a sikeres drill bizonyított verziói. Jövőbeli eltérő verzióknál a kompatibilitást újra ellenőrizni kell.

A 2026-09-02-i automatizált nem nulla regresszió GitHub Actions Ubuntu környezetben, Supabase CLI `2.114.0` mellett futott, és külön pristine local Supabase restore-projektet hozott létre.

## V1 drill és feltárt hiányosság

Az első production backup:

- GitHub Actions run: `33547980831`
- artifact: `ahely-booking-production_20260901T191321Z_387e40d5afcc.tar.gz.age`
- Google Drive upload/read-back SHA-256: PASS
- Backblaze B2 upload/read-back SHA-256: PASS
- encrypted artifact és belső checksumok: PASS
- business schema/data restore platform-kompatibilis local Supabase stackben: PASS
- kritikus üzleti kontrollszámok: PASS

A v1 restore drill azonban feltárta, hogy a `migration-history.sql` kizárólag data-only dump volt. A production `supabase_migrations.schema_migrations` tábla hat mezőt tartalmazott (`version`, `statements`, `name`, `created_by`, `idempotency_key`, `rollback`), míg a friss local Supabase CLI által létrehozott alapstruktúra csak három mezős volt (`version`, `statements`, `name`). Ezért a migration-history önmagában nem volt önleíró és garantáltan visszaállítható.

A hiba feltárása közben egy sima `postgres:17` konténerrel, majd helyi placeholder migrationnel is történt diagnosztikai próba. Ezek **nem részei a végleges restore runbooknak**. A végleges megoldás platform-kompatibilis local Supabase stack + backupVersion 2 lett.

## Javítás – backupVersion 2

A backup pipeline javítva lett:

- új `migration-schema.sql` készül a production `supabase_migrations` sémáról;
- `migration-history.sql` külön data-only dump marad;
- `migration-schema.sql` bekerült a nem üres komponens-ellenőrzésbe;
- bekerült a `DATA_SHA256SUMS` és `SHA256SUMS` fájlokba;
- bekerült a `manifest.json` fájllistába és SHA-256 mezővel rendelkezik;
- backup formátum verziója `2`.

A javítás oka: a migration-history ne függjön attól, hogy egy későbbi vagy local Supabase CLI éppen milyen meta-sémát hoz létre.

## V2 production backup bizonyíték

- GitHub Actions run: `33558905620`
- artifact: `ahely-booking-production_20260901T210519Z_d71300fa8a56.tar.gz.age`
- ugyanazon encrypted artifact Google Drive-ra és Backblaze B2-re feltöltve: PASS
- Google Drive read-back SHA-256: PASS
- Backblaze B2 read-back SHA-256: PASS
- letöltött encrypted artifact `.sha256` sidecar ellenőrzése: PASS (`Match: True`)
- `age` decrypt: PASS
- tar.gz kicsomagolás: PASS
- minden belső `SHA256SUMS` komponens: PASS, beleértve a `migration-schema.sql` és `migration-history.sql` fájlokat.

## Tiszta end-to-end v2 production restore drill

A local Supabase adatbázis nulláról újra lett inicializálva. A korábbi ideiglenes placeholder migration el lett távolítva, majd újabb `supabase db reset --local` futott. A tiszta reset után ugyanabból a v2 artifactból, egy kontrollált tranzakcióban történt a restore:

1. `roles.sql`
2. `schema.sql`
3. `data.sql`
4. a helyi `supabase_migrations` meta séma kontrollált eltávolítása ugyanabban a tranzakcióban (`DROP SCHEMA IF EXISTS ... CASCADE`)
5. production-kori `supabase_migrations` séma visszaállítása a `migration-schema.sql` fájlból
6. `migration-history.sql` visszatöltése

A restore `--single-transaction`, `ON_ERROR_STOP=1` és fail-closed módban történt. A data és migration-history betöltés idején `session_replication_role = replica`, majd `origin` visszaállítás történt.

A pontos, reprodukálható PowerShell parancs a `docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md` dokumentumban szerepel.

### Végső kontrollszámok – 2026-09-01 production artifact

A v2 backup és a tiszta v2 restore eredménye pontosan egyezett:

- `auth_users`: 0
- `profiles`: 0
- `rooms`: 11
- `user_room_permissions`: 0
- `booking_series`: 0
- `bookings_total`: 0
- `bookings_active`: 0
- `bookings_cancelled`: 0
- `booking_cancellations`: 0
- `audit_logs`: 0
- `monthly_settlements`: 0
- `settlement_revisions`: 0
- `settlement_booking_lines`: 0
- `migration_history_rows`: 42

A `migration-history.sql` restore során `COPY 42` futott le, az utóellenőrzés pedig szintén 42 sort adott.

Fontos: a fenti 0/11 értékek a konkrét 2026-09-01-i production artifact forrásállapotát írják le. Jövőbeli drillnél **nem ezek a konstans elvárások**, hanem mindig az adott bundle `control-counts.json` értékei.

## 2026-09-02 – reprezentatív nem nulla adatos M1 restore regresszió

A 2026-09-01-i production artifact üzleti táblái még nagyrészt üresek voltak, ezért külön automatizált regressziós drill készült a nem nulla üzleti adatok bizonyítására.

### Automatizálás

A branchre bekerült:

- `scripts/fixtures/nonzero-restore-fixture.sql`
- `scripts/test-backup-restore-nonzero.sh`
- a drill bekötése a `.github/workflows/database-tests.yml` workflow-ba.

A fixture reprezentatív Auth-, profil-, teremjogosultság-, ismétlődő foglalás-, kivételdátum-, lemondás-, audit- és lezárt havi elszámolási állapotot hoz létre. A backup elkészítését nem teszt-másolat, hanem a tényleges `scripts/backup-production.sh` végzi.

A külső Google Drive és B2 célhelyeket ebben az izolált regresszióban helyi fake rclone remote-ok helyettesítik, így a teszt nem ír éles backup-célhelyre. A titkosítás és visszafejtés valódi `age` folyamattal történik.

### Restore modell

A regresszió a 2026-09-01-i sikeres kézi drill tanulságát reprodukálja:

1. a forrás local Supabase adatbázis migrációkból felépül;
2. a reprezentatív fixture bekerül;
3. a valódi backup script elkészíti a backupVersion 2 bundle-t;
4. encrypted és belső SHA-256 ellenőrzések lefutnak;
5. a forrás Supabase stack leáll;
6. **külön, teljesen új `supabase init` restore-projekt** készül, alkalmazási migrációk nélkül;
7. a teljes restore egy tranzakcióban, `ON_ERROR_STOP=1` módban fut;
8. `roles.sql`, `schema.sql`, `data.sql`, `migration-schema.sql`, `migration-history.sql` visszatöltésre kerül;
9. a source és restored kontrollszámok összehasonlítása megtörténik;
10. RLS, policy, foreign key és booking validation trigger jelenléte külön ellenőrzésre kerül;
11. a restored adatbázison schema lint fut.

Ez fontos: egy már repository-migrációkkal felépített adatbázis **nem** tiszta restore target, mert a teljes `schema.sql` objektumai már léteznének. A regresszió ezért külön pristine Supabase targetet használ.

### PASS bizonyíték

- GitHub Actions workflow: `Database tests`
- run: `33647635924`
- job: `100306833094`
- `Run nonzero backup/restore sandbox drill`: **PASS**
- teljes database-tests job: **PASS**
- pgTAP: `50` fájl, `643` teszt, **PASS**
- konkurenciatesztek: **PASS**

A sandbox artifact:

`ahely-booking-production_20260902T152227Z_930000000000.tar.gz.age`

Ellenőrzések:

- encrypted artifact checksum: PASS
- `roles.sql`: PASS
- `schema.sql`: PASS
- `data.sql`: PASS
- `migration-schema.sql`: PASS
- `migration-history.sql`: PASS
- `control-counts.json`: PASS
- `manifest.json`: PASS
- migration-history restore: `COPY 63`
- RLS/policy/FK/trigger szerkezeti ellenőrzések: PASS

### Nem nulla kontrollszámok – forrás és restore pontos egyezése

- `auth_users`: 2
- `profiles`: 2
- `rooms`: 11
- `user_room_permissions`: 2
- `booking_series`: 1
- `bookings_total`: 13
- `bookings_active`: 12
- `bookings_cancelled`: 1
- `booking_cancellations`: 1
- `audit_logs`: 5
- `monthly_settlements`: 1
- `settlement_revisions`: 1
- `settlement_booking_lines`: 11
- `migration_history_rows`: 63

A végső CI üzenet szerint a fenti kontrollszámok a restore után pontosan egyeztek a forrásállapottal.

A restored adatbázison a schema lint is lefutott. Egy már meglévő, nem restore-integritási warning maradt: `public.create_booking` függvényben a `v_existing_id` változó nincs felhasználva. Ez nem akadályozta a restore-t és nem M1 blocker; külön kódtisztításként kezelhető.

### M1 eredmény

**M1 PASS / a reprezentatív nem nulla adatos backup/restore bizonyíték lezárva.**

Ezzel már nemcsak a production környezetből származó, de üzletileg üres állapot visszaállíthatósága bizonyított, hanem automatizált regresszióval a releváns Auth-, foglalási, törlési, audit- és elszámolási adatok megőrzése is.

A regressziós teszt a database CI része marad, így a backup/restore logikát érintő későbbi változásoknál újra lefuthat.

## Eredmény

**TELJES PASS.**

Bizonyított, hogy a backupVersion 2 formátum:

- létrejön a production adatbázisból;
- client-side titkosítva ugyanaz az artifact kerül mindkét off-site célra;
- mindkét valódi production backup célhelyen read-back checksum ellenőrizhető;
- a titkosított artifact sértetlensége ellenőrizhető;
- a bundle belső komponensei checksum alapján ellenőrizhetők;
- a business schema és adatok tiszta local Supabase környezetbe visszaállíthatók;
- a kritikus üzleti kontrollszámok egyeznek;
- a production-kori migration-meta séma visszaállítható;
- a migration history teljes egészében visszaállítható és konzisztens;
- reprezentatív nem nulla Auth-, jogosultság-, foglalás-, lemondás-, audit- és settlement adatok is pontosan visszaállnak egy külön pristine Supabase restore targetre.

## Kötelező restore sorrend v2 bundle esetén

1. encrypted artifact checksum;
2. decrypt;
3. belső checksumok;
4. platform-kompatibilis izolált **pristine** local Supabase stack, alkalmazási migrációk előzetes ráfuttatása nélkül;
5. `roles.sql`;
6. `schema.sql`;
7. `data.sql`;
8. a helyi `supabase_migrations` meta séma kontrollált cseréje;
9. `migration-schema.sql`;
10. `migration-history.sql`;
11. kritikus kontrollszámok és migration history ellenőrzése;
12. releváns szerkezeti kontrollok ellenőrzése.

## Fontos: a teljes restore PASS nem jelent production GO-t

A backup/restore M1 követelmény teljesült, és a korábbi B2 Object Lock, recovery-key custody, monitoring alert/recovery és Google Drive OAuth-rotációs kapuk is lezárultak. Production azonban továbbra is **NEM GO**, amíg a fennmaradó production-readiness blokkolók nincsenek lezárva:

- #104 független kritikus review lezárása;
- mobil UAT #98 lezárása;
- teljes staging/UAT és production gate ellenőrzés.
