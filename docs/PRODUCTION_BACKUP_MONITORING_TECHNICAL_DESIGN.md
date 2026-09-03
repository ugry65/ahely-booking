# A-Hely foglalási rendszer – Production backup/restore és monitoring technikai terv

Dátum: 2026-08-31
Utolsó státuszfrissítés: 2026-09-02
Kapcsolódó issue: #100
Státusz: **RÉSZBEN IMPLEMENTÁLVA ÉS BACKUP/RESTORE OLDALON TÉNYLEGES DRILLEL VALIDÁLVA**

> **Aktuális reprodukciós forrás:** `docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md`.
>
> **Tényleges restore bizonyíték:** `docs/PRODUCTION_BACKUP_RESTORE_DRILL_PLAN_2026-09-01.md`.
>
> A backup/restore rész 2026-09-01-én teljes end-to-end `backupVersion 2` restore drillel PASS. A monitoring, Object Lock, kulcspéldányok, OAuth token rotáció, független review és további production-readiness gate-ek külön még nyitottak.

## 1. Cél és biztonsági elv

A foglalási adatbázis az elszámolás elsődleges forrása, ezért az adatvesztés nem elfogadható. A backup-rendszer célja nem pusztán mentési fájl készítése, hanem bizonyítottan visszaállítható, auditálható és két független szolgáltatónál tárolt restore-pontok létrehozása.

A production go-live kapu addig zárt, amíg a backup automatizálás, a két külső célhely, a tényleges restore drill és a teljes rendszer monitoring kontrollált teszttel nincs bizonyítva.

## 2. Jóváhagyott üzleti paraméterek

- Időzóna: `Europe/Budapest`.
- Backup időpontok: 08:00, 12:00, 16:00, 20:00.
- Minden futás önálló, időbélyegzett restore-pont.
- Backup célok: Google Drive + Backblaze B2.
- Egyik cél sem helyettesíti a másikat.
- Sikertelennek számít a futás, ha a dump, checksum, titkosítás vagy bármelyik célhelyre történő ellenőrzött feltöltés hibás.
- Production adatot restore-próbánál először csak izolált staging/sandbox célba szabad visszaállítani.

## 3. Backup forrás és tartalom

### 3.1. PostgreSQL / Supabase

Elsődleges eszköz: Supabase CLI `supabase db dump`, nem nyers `pg_dump`.

**Aktuális implementált backupVersion 2** minden futásnál legalább az alábbi fájlokat hozza létre ideiglenes, runner-local könyvtárban:

1. `roles.sql` – `--role-only`;
2. `schema.sql` – séma és adatbázis objektumok;
3. `data.sql` – adatok `--data-only --use-copy` módban;
4. `migration-schema.sql` – a production `supabase_migrations` meta-séma pontos definíciója;
5. `migration-history.sql` – a `supabase_migrations` séma data-only history exportja;
6. `control-counts.json` – kritikus forrásoldali táblaszámok a restore utóellenőrzéséhez;
7. `DATA_SHA256SUMS` – adatkomponensek checksumjai;
8. `manifest.json` – UTC/Budapest időbélyeg, Git commit SHA, Supabase CLI verzió, backup formátum verzió, control-countok és fájl-hash-ek;
9. `SHA256SUMS` – a teljes belső payload ellenőrzőösszegei.

A `migration-schema.sql` 2026-09-01-én, tényleges restore drill során feltárt v1-hiányosság miatt lett kötelező. A migration-history data-only dump önmagában nem elég, mert a production migration meta-séma eltérhet attól, amit egy local vagy későbbi Supabase CLI hoz létre.

A bundle NEM tartalmazhat adatbázis-jelszót, service role kulcsot, OAuth tokent, B2 kulcsot vagy egyéb secretet.

### 3.2. Auth adat

A Supabase Auth felhasználói a PostgreSQL `auth` sémában vannak. A backup/restore elfogadási tesztnek külön bizonyítania kell, hogy a felhasználók és az authentikációhoz szükséges adatbázis-adatok visszaállnak.

A restore runbook külön kezeli azokat a platform-szintű elemeket, amelyek nem pusztán adatbázis-adatok:
- Auth redirect URL-ek;
- API/JWT konfiguráció;
- szükség esetén encryption root key;
- külső auth provider beállítások.

Ezeket nem tesszük bele a backup artifactba. A szükséges recovery secretek külön, GitHubtól, Google Drive-tól és B2-től független biztonságos helyen legyenek tárolva.

### 3.3. Supabase Storage

A repo 2026-08-31-i keresése nem mutat Supabase Storage API-, bucket- vagy upload-használatot. Az MVP backup scope ezért jelenleg adatbázis/Auth-központú.

Fontos: a Supabase adatbázis-backup a Storage objektumok tényleges bináris tartalmát nem menti, csak a metadata kerülhet az adatbázisba. Ha később Storage használat kerül bevezetésre, az objektumok külön exportja és off-site mentése kötelező új backup komponens lesz.

## 4. Artifact készítés és titkosítás

### 4.1. Folyamat

1. Supabase CLI dumpok létrehozása.
2. Fájlok méretének és nem üres állapotának ellenőrzése.
3. Kritikus source control-countok lekérdezése.
4. SHA-256 checksum generálása.
5. Manifest készítése.
6. Egyetlen tömörített bundle létrehozása.
7. Bundle kliensoldali titkosítása.
8. A titkosított artifact hash-ének rögzítése.
9. Ugyanennek a változatlan titkosított artifactnak feltöltése Google Drive-ra és B2-re.
10. Mindkét feltöltés utáni tényleges read-back SHA-256 ellenőrzés.
11. Sikeres heartbeat csak mindkét cél PASS után.

### 4.2. Titkosítás

Implementált megoldás: `age` publikus kulcsos titkosítás.

Előny:
- a backup runnernek csak a publikus recipient kulcs kell;
- a visszafejtési privát kulcs nem kerül GitHub Secrets-be és nem szükséges a napi backuphoz;
- egy runner kompromittálása nem ad automatikusan hozzáférést a régi mentések visszafejtéséhez.

A privát recovery kulcs legalább két, egymástól független, offline/biztonságos helyen legyen elérhető. A kulcs elvesztése a backupok használhatatlanságát jelentené, ezért a kulcs-recovery külön production gate.

## 5. Külső célhelyek

### 5.1. Google Drive

Implementált cél:

- külön backup mappa: `A-Hely-Booking-Production-Backups`;
- timestampes fájlnév;
- `rclone` feltöltés;
- upload utáni teljes artifact read-back és SHA-256 összevetés;
- `.sha256` sidecar read-back összevetés;
- minimális OAuth `drive.file` scope.

### 5.2. Backblaze B2

Implementált cél:

- privát bucket: `ahely-booking-production-backups`;
- külön application key;
- Object Lock képes bucket;
- timestampes objektumkulcs;
- upload utáni teljes artifact read-back és SHA-256 összevetés;
- sidecar read-back összevetés.

Jóváhagyott Object Lock cél: **Governance 30 nap**. Ennek tényleges production konfigurációja és külön bizonyítása továbbra is külön gate, ha még nincs lezárva.

## 6. Automatizálási runner

Implementált irány: GitHub Actions scheduled workflow.

A production workflow:
- `.github/workflows/production-backup.yml`;
- kézi `workflow_dispatch` támogatás;
- kézi futásnál pontos `BACKUP` confirmation szükséges;
- 08:00 / 12:00 / 16:00 / 20:00 Europe/Budapest schedule;
- GitHub `production` environment;
- minimális GitHub permission;
- minden upload/ellenőrzés fail-closed;
- secretet nem logol;
- scheduled futásnál csak a megfelelő időablak heartbeatje kap success pinget.

Megjegyzés: a hosted scheduler nem valós idejű hard-SLA. Ezért a backup freshness monitoringnak az elmaradt futást is észlelnie kell; önmagában a cron beállítás nem bizonyítja az RPO-t.

## 7. Retention – JÓVÁHAGYOTT AKTUÁLIS DÖNTÉS

A korábbi „döntésre előkészített” állapotot a 2026-08-31-i döntés felülírta.

Aktuális retention:

- 0–14 nap: mind a napi 4 restore-pont;
- 15–90 nap: napi 1 restore-pont;
- 3–24 hónap: havi 1 restore-pont.

B2 Governance Object Lock cél: 30 nap, ezért B2-n a rövid távú 0–30 napos restore-pontok törlés ellen védettek legyenek.

Részletes forrás: `docs/DECISION_2026-08-31_BACKUP_RETENTION_OBJECT_LOCK.md`.

## 8. Restore runbook – IMPLEMENTÁLT ÉS VALIDÁLT

Elsődleges reprodukciós forrás:

`docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md`

A tényleges 2026-09-01-i drill jegyzőkönyve:

`docs/PRODUCTION_BACKUP_RESTORE_DRILL_PLAN_2026-09-01.md`

A tényleges drill legfontosabb megállapításai:

- sima `postgres:17` konténer nem tekinthető elegendő Supabase restore célkörnyezetnek;
- platform-kompatibilis local Supabase stack szükséges;
- a v1 migration-history data-only formátum hiányos volt;
- backupVersion 2 külön `migration-schema.sql` komponenssel javította ezt;
- tiszta local Supabase reset után ugyanabból a v2 artifactból `roles.sql + schema.sql + data.sql + migration-schema.sql + migration-history.sql` egy tranzakcióban sikeresen visszaállt;
- source business control-countok és restore utáni control-countok egyeztek;
- migration history `COPY 42`, utóellenőrzés 42 sor.

Bizonyító v2 run:

- GitHub Actions run: `33558905620`;
- artifact: `ahely-booking-production_20260901T210519Z_d71300fa8a56.tar.gz.age`;
- GDrive read-back hash: PASS;
- B2 read-back hash: PASS;
- encrypted local hash: PASS;
- belső checksumok: PASS;
- end-to-end restore: PASS.

### 8.1. Restore acceptance tesztek

Minimum:
- encrypted artifact checksum PASS;
- decrypt PASS;
- minden belső checksum PASS;
- platform-kompatibilis izolált local Supabase stack;
- teljes restore `ON_ERROR_STOP=1` mellett;
- lehetőség szerint egyetlen tranzakció;
- felhasználók/Auth adatok léteznek és source control-counttal egyeznek;
- profile ↔ auth user kapcsolat konzisztens;
- room és user-room jogosultságok helyesek;
- aktív/törölt booking darabszámok és kulcsmezők egyeznek;
- booking series és occurrence kapcsolatok helyesek;
- audit log rekordok megvannak;
- pricing konfiguráció és effective period adatok helyesek;
- havi settlement snapshot/revision adatok konzisztensen visszaálltak;
- kritikus DB függvények/triggerek/RLS szabályok jelen vannak;
- overlap/concurrency védelem regresszióteszt PASS;
- migration schema/history konzisztens.

A 2026-09-01-i production adatállapotban a tényleges nem nulla business kontroll `rooms=11` volt; user/booking/audit/settlement kontrollok 0-k voltak. Éles nem nulla üzleti adatok megjelenése után a drillt meg kell ismételni valós booking/settlement adatokkal is.

## 9. Teljes rendszer health endpoint

Javasolt/implementált endpoint: `GET /api/health`.

Publikus válasz minimális legyen, például:
- `status: ok|degraded|down`;
- általános komponens státuszok;
- szerver által mért válaszidő;
- timestamp;
- verzió/commit rövid azonosító, ha nem érzékeny.

Nem adható vissza:
- DB host;
- Supabase ref, ha nem szükséges;
- SQL vagy stack trace;
- secret;
- user adat;
- belső exception részlet.

Az endpoint végezzen valós, read-only minimális DB ellenőrzést. Ne csak statikus HTTP 200 legyen.

A mélyebb diagnosztika szerverlogban maradjon.

## 10. Külső monitoring

Minimum monitorok:
1. production HTTPS/domain elérhetőség;
2. `/api/health` válasz és kulcsszó/status ellenőrzés;
3. válaszidő tartós romlása;
4. backup heartbeat freshness;
5. GDrive target success;
6. B2 target success;
7. lehetőség szerint SSL/domain expiry.

Aktuális setup irány:
- UptimeRobot Free: külső HTTP/HTTPS health/uptime monitor;
- Healthchecks.io: négy külön backup heartbeat check (08/12/16/20).

A végleges monitoring acceptance drill még külön lezárandó production gate.

## 11. Alerting

Riasztás kell legalább:
- egymást követő health-check hibák;
- DB komponens hiba;
- súlyos/tartós lassulás;
- backup futás failure;
- elmaradt backup a következő elvárt időablakon túl;
- csak GDrive vagy csak B2 upload sikerült;
- recovery/helyreállás.

A backup workflow kétlépcsős státuszt tartson:
- `success`: dump + encrypt + GDrive + B2 + verify PASS;
- `failed/degraded`: bármi más.

Részleges upload soha ne legyen zöld backup.

## 12. Monitoring acceptance drill

Production előtt kontrolláltan bizonyítani kell:
1. health endpoint kényszerített hibája riasztást generál;
2. recovery után recovery értesítés érkezik;
3. DB ellenőrzés hibája külön felismerhető;
4. backup heartbeat elmaradása riasztást generál;
5. egyik backup target hibája degraded/failed állapotot generál;
6. alert ténylegesen eljut az üzemeltetőhöz.

## 13. Implementációs állapot 2026-09-02

### Fázis A – backup mag
- backup script: KÉSZ;
- manifest/checksum: KÉSZ;
- `age` encryption: KÉSZ;
- lokális/sandbox teszt: PASS.

### Fázis B – két célhely
- Google Drive upload + verify: PASS;
- B2 upload + verify: PASS;
- Object Lock konfiguráció: külön még bizonyítandó;
- részleges hibák fail-closed kezelése: tesztelve.

### Fázis C – scheduler/heartbeat
- GitHub Actions 08/12/16/20: implementálva;
- manual run: implementálva;
- heartbeat secret/setup: implementálva;
- kontrollált missed-backup alert drill: még nyitott.

### Fázis D – restore
- reprodukálható runbook: KÉSZ;
- izolált restore: TELJES PASS;
- business control-count ellenőrzés: PASS;
- migration-meta restore: PASS;
- nem nulla production booking/settlement adatokkal ismételt későbbi drill: szükséges, amikor lesz ilyen adat.

### Fázis E – app monitoring
- `/api/health`: implementálva;
- külső uptime monitor: setup elkezdve/konfigurálva;
- alert/recovery kontrollált drill: még nyitott.

### Fázis F – független review
- #104 független review: még kötelező.

## 14. Nem production-ready gate-ek

A backup/restore TELJES PASS önmagában nem jelent production GO-t.

Még külön lezárandó többek között:

- B2 Governance Object Lock 30 nap tényleges konfiguráció és bizonyítás;
- `age` recovery private key két független offline/biztonságos példánya;
- Google Drive OAuth refresh token rotációja a korábbi képernyőkép-expozíció miatt;
- monitoring alert/recovery kontrollált drill;
- #104 független review;
- mobil UAT #98;
- teljes staging/UAT és production gate ellenőrzés.

## 15. Dokumentációs szabály

Backup artifact-formátum, restore sorrend, titkosítás, célhely, retention vagy control-count változtatásakor kötelező frissíteni:

- ezt a technikai dokumentumot;
- `docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md`;
- szükség esetén új restore-drill jegyzőkönyvet;
- PR/issue státuszt.

A cél, hogy egy későbbi beszélgetés a chat-előzmények nélkül, kizárólag a repository aktuális dokumentumaiból reprodukálni tudja a folyamatot.
