# A-Hely – Production backup és restore reprodukálható runbook

Dátum: 2026-09-02
Státusz: **AKTUÁLIS / reprodukálható üzemeltetési runbook**
Kapcsolódó PR: #103
Kapcsolódó issue-k: #100, #101, #102, #104

## 1. A dokumentum célja

Ez a dokumentum az A-Hely production adatbázis off-site backup és izolált restore folyamatának **reprodukálható, lépésről lépésre követhető** leírása.

Célja, hogy egy későbbi fejlesztési beszélgetésben vagy másik AI/fejlesztő/üzemeltető számára a korábbi chat teljes története nélkül is egyértelmű legyen:

- milyen infrastruktúrát építettünk;
- milyen biztonsági döntéseket hoztunk;
- milyen fájlokat tartalmaz a backup;
- hogyan készül, titkosul és kerül két független célhelyre;
- hogyan ellenőrizzük az integritását;
- hogyan állítható vissza izolált Supabase környezetbe;
- milyen hibákat találtunk a tényleges restore drill során;
- hogyan javítottuk ezeket;
- milyen pontos PASS feltételekkel tekinthető a mentés visszaállíthatónak.

Ez a runbook **nem jogosít production in-place restore-ra**. Production adatbázis visszaállítása kizárólag tényleges incidensnél, külön dokumentált döntéssel történhet.

---

## 2. Elsődleges források és elsőbbség

A backup/restore blokk aktuális forrásai:

1. `scripts/backup-production.sh` – a tényleges backup implementáció;
2. `.github/workflows/production-backup.yml` – az ütemezett production backup workflow;
3. `docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md` – ez a reprodukálható eljárás;
4. `docs/PRODUCTION_BACKUP_RESTORE_DRILL_PLAN_2026-09-01.md` – a tényleges 2026-09-01-i drill bizonyítéka;
5. `docs/PRODUCTION_BACKUP_MONITORING_TECHNICAL_DESIGN.md` – technikai terv és architektúra;
6. `docs/DECISION_2026-08-31_BACKUP_RETENTION_OBJECT_LOCK.md` – retention/Object Lock döntés;
7. PR #103 – aktuális implementation/evidence összefoglaló.

A régebbi `docs/BACKUP_RESTORE_STRATEGIA.md` történeti baseline. Ha retention, célhely, gyakoriság vagy artifact-formátum kérdésben eltérés van, a fenti frissebb dokumentumok és az aktuális kód az irányadó.

---

## 3. Jóváhagyott production backup architektúra

### 3.1. Forrás

Production Supabase projekt:

- név: `ahely-booking-production`;
- project ref: `yasrmxwjojepessivhmc`;
- régió: `eu-west-2` / London;
- PostgreSQL család: 17.x.

A backup logikai dumpot készít a production PostgreSQL adatbázisról. A backup workflow **nem írhat production üzleti táblába**.

### 3.2. Külső célhelyek

Ugyanaz a már titkosított artifact két egymástól független helyre kerül:

1. Google Drive;
2. Backblaze B2.

Google Drive mappa:

`A-Hely-Booking-Production-Backups`

Backblaze bucket:

`ahely-booking-production-backups`

A B2 bucket privát, titkosítást használ és Object Lock képes. A jóváhagyott cél a Governance 30 napos Object Lock.

### 3.3. Backup időpontok

Időzóna: `Europe/Budapest`.

Minden nap:

- 08:00;
- 12:00;
- 16:00;
- 20:00.

Ez nappal 4 órás névleges RPO-t, a 20:00–08:00 közötti időszakban 12 órás elfogadott maximális rést jelent.

### 3.4. Retention

Aktuális döntés:

- 0–14 nap: napi 4 restore-pont;
- 15–90 nap: napi 1 restore-pont;
- 3–24 hónap: havi 1 restore-pont;
- B2 Governance Object Lock cél: 30 nap.

A részletes retention döntés forrása: `docs/DECISION_2026-08-31_BACKUP_RETENTION_OBJECT_LOCK.md`.

---

## 4. Titkosítás és kulcskezelés

Titkosítás: `age` publikus kulcsos titkosítás.

A GitHub workflow csak a **publikus recipient kulcsot** ismeri:

Repository variable:

`BACKUP_AGE_RECIPIENT`

A recovery private key nem kerülhet:

- GitHubba;
- GitHub Secrets-be;
- Google Drive backup mappába;
- B2 bucketbe;
- e-mailbe;
- chatbe;
- screenshotra.

A 2026-09-01-i drill alatt a privát kulcs Windows gépen ezen a helyen volt:

`$HOME\Documents\ahely-backup-age-key.txt`

Ez útvonal csak a drill gép aktuális helye, nem kötelező jövőbeli szabvány.

Production-ready állapot előtt a recovery private key legalább **két egymástól független offline/biztonságos példányban** legyen megőrizve.

---

## 5. GitHub konfiguráció

### 5.1. Repository variables

A backup pipeline az alábbi repository variable-öket használja:

- `BACKUP_AGE_RECIPIENT`
- `BACKUP_GDRIVE_REMOTE`
- `BACKUP_B2_REMOTE`

Aktuális logikai értékek:

- `BACKUP_GDRIVE_REMOTE` → `gdrive:A-Hely-Booking-Production-Backups`
- `BACKUP_B2_REMOTE` → `b2:ahely-booking-production-backups`

A `gdrive:` itt a GitHub workflow rclone remote neve. A 2026-09-01-i Windows drill gépen a helyi remote neve `gdrive2:` volt. A két név eltérése szándékos, környezetfüggő.

### 5.2. GitHub Secrets

A szükséges secret-nevek:

- `SUPABASE_PRODUCTION_DB_URL`
- `BACKUP_GDRIVE_CLIENT_ID`
- `BACKUP_GDRIVE_CLIENT_SECRET`
- `BACKUP_GDRIVE_RCLONE_TOKEN`
- `BACKUP_B2_ACCOUNT_ID`
- `BACKUP_B2_APPLICATION_KEY`
- `BACKUP_HEARTBEAT_08_URL`
- `BACKUP_HEARTBEAT_12_URL`
- `BACKUP_HEARTBEAT_16_URL`
- `BACKUP_HEARTBEAT_20_URL`

Secret értékeket dokumentációba vagy logba írni tilos.

### 5.3. Külön ismert security blocker

A beállítás során egy Google Drive OAuth refresh token korábban képernyőképen láthatóvá vált. Emiatt production-ready állapot előtt kötelező:

1. a régi OAuth grant/token visszavonása;
2. friss rclone token generálása;
3. `BACKUP_GDRIVE_RCLONE_TOKEN` frissítése;
4. GDrive target és dual-target backup újraellenőrzése.

A technikai folyamat ettől jelenleg működik, de ez production security gate.

---

## 6. Backup workflow

Workflow fájl:

`.github/workflows/production-backup.yml`

A workflow:

- támogat kézi `workflow_dispatch` indítást;
- kézi indításnál a confirmation értéke pontosan `BACKUP`;
- scheduled futásban 08/12/16/20 órakor indul;
- GitHub `production` environmentet használ;
- Supabase CLI verziója a jelenlegi workflow-ban `2.116.0`;
- telepíti az `age`, `rclone`, `jq`, `postgresql-client` eszközöket;
- csak sikeres teljes backup után küld heartbeatet.

A backup success definíciója:

**dump + control-count + checksum + manifest + tar + age encrypt + GDrive upload/readback verify + B2 upload/readback verify = PASS**.

Ha bármelyik komponens hibás, a futás hibás. Részleges egycélos backup nem számít sikeresnek.

---

## 7. BackupVersion 2 artifact-formátum

A tényleges implementáció: `scripts/backup-production.sh`.

Artifact névformátum:

`ahely-booking-production_YYYYMMDDTHHMMSSZ_<git-short-sha>.tar.gz.age`

Mellette:

`ahely-booking-production_YYYYMMDDTHHMMSSZ_<git-short-sha>.tar.gz.age.sha256`

### 7.1. Bundle tartalma

A visszafejtett/tömörített v2 bundle tartalma:

- `roles.sql`
- `schema.sql`
- `data.sql`
- `migration-schema.sql`
- `migration-history.sql`
- `control-counts.json`
- `DATA_SHA256SUMS`
- `manifest.json`
- `SHA256SUMS`

### 7.2. Az egyes fájlok szerepe

`roles.sql`

- Supabase CLI `--role-only` dump;
- adatbázis szerepkör-konfiguráció.

`schema.sql`

- alkalmazási és platform adatbázis séma/objektumok dumpja.

`data.sql`

- `--data-only --use-copy`;
- üzleti és Auth adatok;
- kizárás: `storage.buckets_vectors`, `storage.vector_indexes`.

`migration-schema.sql`

- a production `supabase_migrations` séma **szerkezetének** dumpja;
- azért kötelező, mert a migration-history adata önmagában nem önleíró.

`migration-history.sql`

- a production `supabase_migrations` séma data-only dumpja.

`control-counts.json`

Forrásoldali kontrollszámok. Jelenlegi script legalább ezeket rögzíti:

- `auth_users`
- `profiles`
- `rooms`
- `user_room_permissions`
- `booking_series`
- `bookings_total`
- `bookings_active`
- `bookings_cancelled`
- `booking_cancellations`
- `audit_logs`
- `monthly_settlements`
- `settlement_revisions`
- `settlement_booking_lines`

`DATA_SHA256SUMS`

- a fő adatkomponensek hash-e.

`manifest.json`

Tartalmazza többek között:

- `backupVersion: "2"`;
- UTC időbélyeg;
- Budapest időbélyeg;
- Git SHA;
- Supabase CLI verzió;
- control-countok;
- komponensenként SHA-256.

`SHA256SUMS`

- a teljes belső payload komponenseinek checksum listája, a manifesttel együtt.

---

## 8. Backup pipeline részletes működése

A `scripts/backup-production.sh` fail-closed módon működik:

1. `set -Eeuo pipefail`;
2. `umask 077`;
3. ellenőrzi a szükséges parancsokat;
4. ellenőrzi a kötelező environment variable-öket;
5. ideiglenes privát munkakönyvtárat hoz létre;
6. EXIT-kor törli az ideiglenes könyvtárat;
7. elkészíti a dump komponenseket;
8. ellenőrzi, hogy egyik kötelező komponens sem üres;
9. read-only SQL lekérdezéssel elkészíti a `control-counts.json` fájlt;
10. validálja a JSON formátumot;
11. checksumokat készít;
12. elkészíti a manifestet;
13. tar.gz bundle-t készít;
14. `age`-dzsel titkosítja;
15. elkészíti a titkosított artifact `.sha256` sidecarját;
16. ugyanazt az encrypted artifactot feltölti GDrive-ra;
17. GDrive-ról visszaolvassa és újra SHA-256-olja;
18. a GDrive sidecart is visszaolvassa és byte/logikai tartalomra összeveti;
19. ugyanazt elvégzi B2-n;
20. csak mindkét cél PASS után tekinti késznek a backupot;
21. heartbeatet csak teljes siker után küld.

A workflow nem ír production üzleti táblába.

---

## 9. 2026-09-01 bizonyító v2 backup

GitHub Actions run:

`33558905620`

Artifact:

`ahely-booking-production_20260901T210519Z_d71300fa8a56.tar.gz.age`

Bizonyított:

- production dump PASS;
- `migration-schema.sql` létrejött;
- Google Drive upload PASS;
- Google Drive read-back SHA-256 PASS;
- Backblaze B2 upload PASS;
- Backblaze B2 read-back SHA-256 PASS;
- ugyanaz a titkosított artifact volt mindkét célon.

Ez a konkrét artifact lett a teljes v2 restore drill forrása.

---

## 10. Restore környezet – követelmény

Restore drillhez **nem elegendő egy sima `postgres:17` Docker image**.

A tényleges drill bizonyította, hogy a Supabase platform-specifikus szerepkörök, Auth séma és extensionök miatt platform-kompatibilis Supabase local stack szükséges.

A sikeres drill környezetében:

- Docker CLI: `29.7.2`;
- Docker Desktop + WSL2;
- Supabase CLI: `2.116.0`;
- local Supabase PostgreSQL image: `ghcr.io/supabase/postgres:17.6.1.165`;
- rclone: `1.75.0`;
- age: `1.3.1`;
- Node: `v24.18.0`.

Ezek a bizonyított drill verziók. Jövőbeli restore-nál eltérő verzió használható, de eltérés esetén kompatibilitást újra bizonyítani kell.

---

## 11. Windows előfeltételek – reprodukció

A 2026-09-01-i drill Windows PowerShellből történt.

Szükséges:

- Docker Desktop;
- működő WSL2;
- Node/npm;
- Supabase CLI (`npx.cmd supabase` használható);
- rclone;
- age;
- recovery private key helyben.

### 11.1. Docker Desktop

Telepítéshez a drill során használt parancs:

```powershell
winget install -e --id Docker.DockerDesktop
```

Ha Docker Desktop azt jelzi, hogy a WSL túl régi:

```powershell
wsl --update
```

Ezután Docker Desktop újraindítás szükséges lehet.

Ellenőrzés:

```powershell
docker --version
docker info
```

### 11.2. Supabase CLI PowerShell alatt

A gépen a PowerShell execution policy miatt az `npx` `.ps1` wrapper tiltva volt. A működő megoldás:

```powershell
npx.cmd supabase --version
```

A drill során ez `2.116.0` verziót adott.

---

## 12. Izolált local Supabase stack létrehozása

Hozz létre külön restore könyvtárat:

```powershell
$local = "$HOME\Documents\ahely-supabase-restore"
New-Item -ItemType Directory -Force $local | Out-Null
Set-Location $local
```

Inicializálás:

```powershell
npx.cmd supabase init
```

Indítás:

```powershell
npx.cmd supabase start
```

A sikeres indulás megjeleníti többek között a local Project URL-t, Database URL-t és Studio URL-t.

A local kulcsok fejlesztői kulcsok, de nem szükséges őket dokumentációba vagy chatbe másolni.

Konténernév ellenőrzése:

```powershell
docker ps --format "table {{.Names}}\t{{.Image}}" | Select-String "supabase_db"
```

A drillben a konténer neve:

`supabase_db_ahely-supabase-restore`

A jövőben a név a könyvtár/projekt nevétől függhet.

---

## 13. Platform-kompatibilitás előellenőrzés

Ajánlott ellenőrzés restore előtt.

Auth audit tábla:

```powershell
docker exec supabase_db_ahely-supabase-restore `
  psql -U postgres -d postgres `
  -c "select ordinal_position, column_name, data_type from information_schema.columns where table_schema='auth' and table_name='audit_log_entries' order by ordinal_position;"
```

A 2026-09-01-i kompatibilis stackben szerepelt az `ip_address` oszlop.

Supabase role-ok:

```powershell
docker exec supabase_db_ahely-supabase-restore `
  psql -U postgres -d postgres `
  -c "select rolname, rolsuper, rolcanlogin from pg_roles where rolname in ('supabase_admin','supabase_realtime_admin') order by rolname;"
```

Elvárt: mindkét role létezzen.

---

## 14. Restore artifact letöltése Google Drive-ról

A drill gépen a helyi rclone remote neve `gdrive2:` volt.

Remote-ok ellenőrzése:

```powershell
rclone listremotes
```

Backup lista:

```powershell
rclone lsf gdrive2:A-Hely-Booking-Production-Backups
```

Általános változók:

```powershell
$dir = "$HOME\Documents\ahely-restore-drill"
New-Item -ItemType Directory -Force $dir | Out-Null
$artifactName = "<KIVALASZTOTT_ARTIFACT>.tar.gz.age"
```

Artifact letöltés:

```powershell
rclone copyto `
  "gdrive2:A-Hely-Booking-Production-Backups/$artifactName" `
  "$dir\$artifactName"
```

Sidecar letöltés:

```powershell
rclone copyto `
  "gdrive2:A-Hely-Booking-Production-Backups/$artifactName.sha256" `
  "$dir\$artifactName.sha256"
```

A bizonyító drill konkrét fájlja:

`ahely-booking-production_20260901T210519Z_d71300fa8a56.tar.gz.age`

---

## 15. Külső encrypted artifact integritásellenőrzése

```powershell
$artifact = Join-Path $dir $artifactName
$sidecar = Join-Path $dir "$artifactName.sha256"

$expected = (Get-Content $sidecar).Split()[0].Trim().ToLower()
$actual = (Get-FileHash $artifact -Algorithm SHA256).Hash.ToLower()

"Expected: $expected"
"Actual:   $actual"
"Match:    $($expected -eq $actual)"
```

PASS feltétel:

`Match: True`

Ha `False`, **STOP**. Ne decryptelj és ne restore-olj sérült artifactból.

---

## 16. Decrypt

Példa:

```powershell
$key = "$HOME\Documents\ahely-backup-age-key.txt"
$output = Join-Path $dir ($artifactName -replace '\.age$','')

age --decrypt -i $key -o $output $artifact
```

A private key tartalmát nem szabad terminálba kiíratni vagy megosztani.

---

## 17. Bundle kibontása

```powershell
$extract = Join-Path $dir "extracted-v2"
New-Item -ItemType Directory -Force $extract | Out-Null

tar -xzf $output -C $extract
Get-ChildItem $extract
```

BackupVersion 2 esetén kötelezően jelen legyen legalább:

- `roles.sql`
- `schema.sql`
- `data.sql`
- `migration-schema.sql`
- `migration-history.sql`
- `control-counts.json`
- `manifest.json`
- `SHA256SUMS`

---

## 18. Belső checksum ellenőrzés

PowerShell:

```powershell
Get-Content (Join-Path $extract "SHA256SUMS") | ForEach-Object {
    if ($_ -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
        $expected = $matches[1].ToLower()
        $file = $matches[2].Trim()
        $path = Join-Path $extract $file
        $actual = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()

        if ($expected -eq $actual) {
            "PASS  $file"
        } else {
            "FAIL  $file"
        }
    }
}
```

Minden felsorolt komponensnek `PASS` eredményt kell adnia.

Bármely `FAIL` esetén **STOP**.

---

## 19. Fontos történeti finding – miért lett backupVersion 2

A v1 bundle tartalmazott `migration-history.sql` fájlt, de nem tartalmazta a production `supabase_migrations` séma definícióját.

A v1 restore során kiderült:

- a production `schema_migrations` history adat 6 mezőt használt:
  - `version`
  - `statements`
  - `name`
  - `created_by`
  - `idempotency_key`
  - `rollback`
- a friss local Supabase CLI által létrehozott alap `schema_migrations` tábla csak 3 mezős volt:
  - `version`
  - `statements`
  - `name`

Következmény: a data-only migration-history dump nem volt önállóan visszaállítható.

Javítás:

- backupVersion 2 bevezetése;
- új `migration-schema.sql` komponens;
- checksum/manifest frissítése;
- restore során production-kori migration séma visszaállítása a history előtt.

Ez a finding a restore drill egyik legfontosabb eredménye.

---

## 20. Egyszeri hibakeresési lépések – NEM részei a normál runbooknak

A 2026-09-01-i vizsgálat alatt több diagnosztikai kerülőút történt. Ezeket **nem kell normál restore-nál megismételni**:

- sima `postgres:17` konténer próbája;
- kézi `supabase_migrations` struktúra találgatása;
- `00000000000000_restore_init.sql` placeholder migration létrehozása;
- `supabase migration repair` kísérlet;
- placeholder history tábla létrehozása csak a CLI aktuális struktúrájának megfigyeléséhez.

Ezek diagnosztikai lépések voltak a v1 hiányosság okának azonosítására.

A normál v2 restore ezeket **nem igényli**.

---

## 21. Tiszta restore drill előkészítése

Ha korábbi teszt futott ugyanabban a local Supabase projektben:

```powershell
npx.cmd supabase db reset --local
```

A tiszta drillben a `supabase/migrations` könyvtárban ne legyen diagnosztikai placeholder migration.

A 2026-09-01-i végső bizonyító futás előtt a korábban létrehozott placeholder fájlt eltávolítottuk, majd újra `db reset --local` futott.

A tiszta reset után nem jelent meg többé:

`Applying migration 00000000000000_restore_init.sql`

---

## 22. V2 restore fájlok bemásolása a DB konténerbe

```powershell
$extract = "$HOME\Documents\ahely-restore-drill\extracted-v2"
$dbContainer = "supabase_db_ahely-supabase-restore"

docker cp "$extract\roles.sql" "$dbContainer`:/tmp/roles.sql"
docker cp "$extract\schema.sql" "$dbContainer`:/tmp/schema.sql"
docker cp "$extract\data.sql" "$dbContainer`:/tmp/data.sql"
docker cp "$extract\migration-schema.sql" "$dbContainer`:/tmp/migration-schema.sql"
docker cp "$extract\migration-history.sql" "$dbContainer`:/tmp/migration-history.sql"
```

Ha a local projekt neve eltér, a `$dbContainer` értékét a `docker ps` alapján módosítani kell.

---

## 23. Teljes end-to-end v2 restore – bizonyított parancs

A sikeres 2026-09-01-i végső restore egyetlen tranzakcióban futott:

```powershell
docker exec supabase_db_ahely-supabase-restore `
  psql `
  -U supabase_admin `
  -d postgres `
  --single-transaction `
  --variable ON_ERROR_STOP=1 `
  --file /tmp/roles.sql `
  --file /tmp/schema.sql `
  --command "SET session_replication_role = replica" `
  --file /tmp/data.sql `
  --command "SET session_replication_role = origin" `
  --command "DROP SCHEMA IF EXISTS supabase_migrations CASCADE" `
  --file /tmp/migration-schema.sql `
  --command "SET session_replication_role = replica" `
  --file /tmp/migration-history.sql `
  --command "SET session_replication_role = origin"
```

### Miért így?

`--single-transaction`

- a teljes restore egy tranzakció;
- hiba esetén nincs elfogadható félkész állapot.

`ON_ERROR_STOP=1`

- az első SQL hibánál a `psql` megáll.

`session_replication_role = replica`

- data/history betöltés alatt szükséges trigger/replication viselkedés kontrollálására.

`DROP SCHEMA IF EXISTS supabase_migrations CASCADE`

- biztosítja, hogy egy local/future CLI által esetleg létrehozott eltérő migration-meta tábla ne akadályozza a production-kori séma visszaállítását;
- ugyanabban a tranzakcióban történik, ezért hiba esetén rollbackel.

`migration-schema.sql` a `migration-history.sql` előtt

- a history pontos production-kori struktúrába töltődik.

---

## 24. Forrás kontrollszámok megtekintése

A restore előtt/után a bundle-ben lévő forrásértékek:

```powershell
Get-Content "$extract\control-counts.json"
```

A 2026-09-01-i bizonyító production állapot:

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

Ezek **nem általános elvárt konstansok**. Jövőbeli restore-nál mindig az adott artifact `control-counts.json` értékei az elvártak.

---

## 25. Restore utáni kontroll lekérdezés

A bizonyított ellenőrző lekérdezés:

```powershell
docker exec supabase_db_ahely-supabase-restore `
  psql -U supabase_admin -d postgres -A -t `
  -c "select json_build_object(
    'auth_users', (select count(*) from auth.users),
    'profiles', (select count(*) from public.profiles),
    'rooms', (select count(*) from public.rooms),
    'user_room_permissions', (select count(*) from public.user_room_permissions),
    'booking_series', (select count(*) from public.booking_series),
    'bookings_total', (select count(*) from public.bookings),
    'bookings_active', (select count(*) from public.bookings where status='active'),
    'bookings_cancelled', (select count(*) from public.bookings where status='cancelled'),
    'booking_cancellations', (select count(*) from public.booking_cancellations),
    'audit_logs', (select count(*) from public.audit_logs),
    'monthly_settlements', (select count(*) from public.monthly_settlements),
    'settlement_revisions', (select count(*) from public.settlement_revisions),
    'settlement_booking_lines', (select count(*) from public.settlement_booking_lines),
    'migration_history_rows', (select count(*) from supabase_migrations.schema_migrations)
  );"
```

A business kontrollokat az artifact `control-counts.json` fájljával kell összevetni.

A migration history sorainak számát a restore output (`COPY N`) és az utólagos DB count együtt bizonyítja.

---

## 26. 2026-09-01 teljes end-to-end v2 PASS bizonyíték

A tiszta local Supabase reset után ugyanabból a v2 artifactból visszaállt:

- `roles.sql`: PASS;
- `schema.sql`: PASS;
- `data.sql`: PASS;
- `migration-schema.sql`: PASS;
- `migration-history.sql`: PASS.

Migration history betöltés:

`COPY 42`

Utóellenőrzés:

`migration_history_rows = 42`

Végső business kontroll:

- `rooms = 11`;
- minden további, a source artifactban rögzített business kontroll = 0.

Ez pontosan egyezett a v2 artifact forrásoldali kontrolladataival.

**Eredmény: TELJES END-TO-END V2 RESTORE DRILL PASS a 2026-09-01-i production adatállapoton.**

---

## 27. PASS / FAIL döntési szabály

Restore PASS csak akkor mondható ki, ha egyszerre teljesül:

1. az encrypted artifact sidecar SHA-256 egyezik;
2. az `age` decrypt sikeres;
3. minden belső `SHA256SUMS` PASS;
4. platform-kompatibilis izolált Supabase környezetet használunk;
5. a teljes restore `ON_ERROR_STOP=1` mellett hiba nélkül fut;
6. nincs részleges restore;
7. minden business control-count egyezik az artifact `control-counts.json` értékével;
8. migration schema restore sikeres;
9. migration history restore sikeres;
10. migration history utóellenőrzés konzisztens.

Bármely eltérés esetén az eredmény FAIL vagy INVESTIGATE, nem PASS.

---

## 28. Restore drill korlátja – jelenlegi production adatok

A bizonyító drill idején productionben:

- 11 room volt;
- user = 0;
- booking = 0;
- audit = 0;
- settlement = 0.

Ez bizonyítja a technikai restore-láncot és a nem üres room adatok visszaállítását, de nem bizonyít még valós, nem nulla foglalási/pénzügyi adatokon végzett helyreállítást.

Amint productionben tényleges üzleti adatok vannak, célszerű és production üzemeltetésben negyedévente kötelező megismételni a drillt, különösen nem nulla:

- Auth user;
- profile;
- booking;
- cancelled booking;
- audit log;
- settlement/revision adatokkal.

---

## 29. A restore után ajánlott további alkalmazási tesztek

Az egyszerű count-egyezésen túl éles adatokkal végzett későbbi drillnél kötelezően vagy erősen ajánlott:

- Auth user ↔ profile kapcsolatok ellenőrzése;
- room permission mintavétel;
- aktív és törölt booking rekordok mintavételes összevetése;
- booking overlap DB constraint ellenőrzése;
- RLS státuszok;
- kritikus RPC-k;
- audit trigger/immutabilitás;
- pricing konfiguráció;
- havi settlement snapshot/revision;
- alkalmazási smoke teszt a restaurált DB ellen.

---

## 30. Cleanup local drill után

A local restore környezet csak tesztkörnyezet.

Ha már nincs rá szükség:

```powershell
Set-Location "$HOME\Documents\ahely-supabase-restore"
npx.cmd supabase stop
```

Ha az izolált környezetet végleg törölni akarjuk, előtte ellenőrizni kell, hogy nincs benne egyetlen szükséges bizonyíték vagy lokálisan egyedüli recovery fájl sem.

A recovery private key törlése **nem** része a cleanupnak.

---

## 31. Ismert még nyitott production gate-ek

A teljes restore PASS nem jelenti azt, hogy a teljes infrastruktúra production-ready.

Még külön lezárandó:

- B2 Governance Object Lock 30 nap tényleges konfiguráció és bizonyítás;
- recovery private key két független offline/biztonságos példánya;
- Google Drive OAuth token rotáció;
- monitoring alert + recovery kontrollált drill;
- #104 független review;
- mobil UAT #98;
- teljes staging/UAT és production readiness ellenőrzés.

---

## 32. Reprodukciós gyorslista

Ha egy jövőbeli beszélgetésben a restore-t újra kell futtatni, a minimális sorrend:

1. olvasd el ezt a runbookot;
2. ellenőrizd a legfrissebb `scripts/backup-production.sh` kódot;
3. válassz v2 vagy újabb backup artifactot;
4. izolált Supabase local/sandbox környezet;
5. artifact + sidecar letöltés;
6. encrypted SHA-256 ellenőrzés;
7. `age` decrypt;
8. belső SHA-256 ellenőrzés;
9. tiszta DB reset;
10. öt SQL komponens bemásolása;
11. teljes tranzakciós restore;
12. business control-count összevetés;
13. migration history ellenőrzés;
14. dokumentáld a run/artifact/hash/eredményt;
15. csak minden egyezés után PASS.

---

## 33. Dokumentációs változtatási szabály

Ha a backup artifact formátuma, a backup célhely, a titkosítás, a restore sorrend, a control-count lista vagy a retention változik, ezt a dokumentumot ugyanabban a fejlesztési szeletben frissíteni kell.

A runbook célja, hogy a következő restore ne korábbi chat-emlékezetből, hanem ellenőrizhető projektforrásból legyen végrehajtható.
