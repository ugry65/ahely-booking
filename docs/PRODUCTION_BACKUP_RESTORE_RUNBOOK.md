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

### Dokumentum-karbantartási szabály

Ez a runbook a backup/restore blokk elsődleges operatív leírása. Ha a backup script, artifact-formátum, célhely, titkosítás, restore sorrend, control-count lista, scheduler, kulcskezelés vagy retention változik, ezt a dokumentumot **ugyanabban a fejlesztési szeletben** frissíteni kell. A runbook frissítése nélkül a backup/restore módosítás dokumentációs szempontból nem tekinthető lezártnak.

### Forrásütközés kezelése

Ha ez a runbook és a tényleges implementáció között eltérés van, **a repository aktuális kódja nem értelmezhető automatikusan helyesebb üzleti döntésként**. Ilyenkor STOP/INVESTIGATE szükséges: össze kell vetni a változtatás commitját, a kapcsolódó döntési dokumentumot és a drill bizonyítékát, majd a dokumentációt és/vagy implementációt konzisztenssé kell tenni. Kritikus restore-t nem szabad bizonytalan forráselsőbbséggel végrehajtani.

---

## 2. Elsődleges források és elsőbbség

A backup/restore blokk aktuális forrásai:

1. `scripts/backup-production.sh` – a tényleges backup implementáció;
2. `.github/workflows/production-backup.yml` – az ütemezett production backup workflow;
3. `docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md` – ez a reprodukálható eljárás;
4. `docs/PRODUCTION_BACKUP_RESTORE_DRILL_PLAN_2026-09-01.md` – a tényleges 2026-09-01-i drill bizonyítéka;
5. `docs/PRODUCTION_BACKUP_MONITORING_TECHNICAL_DESIGN.md` – technikai terv és architektúra;
6. `docs/DECISION_2026-08-31_BACKUP_RETENTION_OBJECT_LOCK.md` – retention/Object Lock döntés;
7. `docs/DECISION_2026-09-02_AGE_RECOVERY_KEY_CUSTODY.md` – recovery private key megőrzési döntés;
8. PR #103 – aktuális implementation/evidence összefoglaló.

A régebbi `docs/BACKUP_RESTORE_STRATEGIA.md` történeti baseline. Ha retention, célhely, gyakoriság vagy artifact-formátum kérdésben eltérés van, a fenti frissebb dokumentumok és az aktuális kód az irányadó, de ellentmondás esetén a fenti STOP/INVESTIGATE szabály érvényes.

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

Production-ready állapot előtt a recovery private key legalább **két egymástól független, a tulajdonos által kontrollált példányban** legyen megőrizve. Az elfogadott 2026-09-02-i megoldás:

1. egy példány a tulajdonos saját NAS rendszerén;
2. egy második példány ettől független másik meghajtón.

Nem követelmény két fizikailag offline USB-adathordozó. A két másolatnak azonban külön hibadomént kell képviselnie; ugyanazon NAS két mappája, ugyanazon fizikai lemez két partíciója vagy ugyanazon eszköz két mappája nem számít két független példánynak.

A részletes aktuális döntés forrása: `docs/DECISION_2026-09-02_AGE_RECOVERY_KEY_CUSTODY.md`.

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
- ugyanaz a titkosított artifact került mindkét célhelyre;
- restore drill során külső és belső checksum PASS;
- tiszta local Supabase környezetből end-to-end restore PASS;
- végső kontroll: `rooms=11`, minden további rögzített üzleti kontroll 0, `migration_history_rows=42`.

## 10. Monitoring és Object Lock bizonyítékok

- B2 Object Lock: Governance / 30 nap, B2 API-val bizonyított 2026-09-02-án.
- Healthchecks.io backup heartbeat alert + recovery drill: PASS 2026-09-02-án.
- Kontrollált failure jelzés után DOWN e-mail megérkezett.
- 45 másodperces várakozás után recovery ping és UP e-mail megérkezett.
- A drill nem érintette a production adatbázist vagy a backup artifactokat.

## 11. Production-ready előtt még kötelező

- a recovery private key két független példányának megőrzése a `docs/DECISION_2026-09-02_AGE_RECOVERY_KEY_CUSTODY.md` szerint;
- a korábban képernyőképen megjelent Google Drive OAuth refresh token rotációja;
- #104 független review lezárása;
- mobil UAT #98 lezárása;
- teljes staging/UAT és production gate ellenőrzés.

## 12. Gate

A backup/restore és heartbeat monitoring technikailag bizonyított, de a rendszer ettől még nem production-ready. Nincs automatikus `main` merge és nincs production deploy.
