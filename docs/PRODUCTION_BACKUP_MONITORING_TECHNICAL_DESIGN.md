# A-Hely foglalási rendszer – Production backup/restore és monitoring technikai terv

Dátum: 2026-08-31
Kapcsolódó issue: #100
Státusz: TECHNIKAI TERV – implementáció előtt

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

Minden backup futás legalább az alábbi fájlokat hozza létre ideiglenes, runner-local könyvtárban:

1. `roles.sql` – `--role-only`;
2. `schema.sql` – séma és adatbázis objektumok;
3. `data.sql` – adatok `--data-only --use-copy` módban;
4. `migration-history.sql` – `supabase_migrations` séma adatainak külön exportja, ha a fő dump nem biztosítja a szükséges visszaállítási bizonyítékot;
5. `manifest.json` – projekt/ref, UTC és Europe/Budapest időbélyeg, Git commit SHA, Supabase CLI verzió, Postgres verzió, fájlméretek, hash-ek és backup pipeline verzió;
6. `SHA256SUMS` – minden bundle-tag ellenőrzőösszege.

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
3. SHA-256 checksum generálása.
4. Manifest készítése.
5. Egyetlen tömörített bundle létrehozása.
6. Bundle kliensoldali titkosítása.
7. A titkosított artifact hash-ének rögzítése.
8. Ugyanennek a változatlan titkosított artifactnak feltöltése Google Drive-ra és B2-re.
9. Mindkét feltöltés utáni objektum/file metadata ellenőrzés.
10. Sikeres heartbeat csak mindkét cél PASS után.

### 4.2. Titkosítás

Javasolt megoldás: `age` publikus kulcsos titkosítás.

Előny:
- a backup runnernek csak a publikus recipient kulcs kell;
- a visszafejtési privát kulcs nem kerül GitHub Secrets-be és nem szükséges a napi backuphoz;
- egy runner kompromittálása nem ad automatikusan hozzáférést a régi mentések visszafejtéséhez.

A privát recovery kulcs legalább két, egymástól független, offline/biztonságos helyen legyen elérhető. A kulcs elvesztése a backupok használhatatlanságát jelentené, ezért a kulcs-recovery külön production gate.

## 5. Külső célhelyek

### 5.1. Google Drive

- külön backup mappa;
- timestampes fájlnév, felülírás tiltva;
- upload után file ID/méret/hash vagy más megfelelő integritási meta ellenőrzés;
- jogosultság minimális szükséges scope-ra korlátozva;
- OAuth/service credential csak secret store-ban.

### 5.2. Backblaze B2

- privát bucket;
- külön application key minimális jogosultsággal;
- Object Lock bekapcsolva;
- timestampes objektumkulcs, nincs overwrite;
- upload utáni méret/hash ellenőrzés;
- retention implementáció csak a külön jóváhagyott retention döntés után.

Első technikai irány: Governance jellegű törlésvédelem, mert a Compliance mód visszafordíthatatlansága üzemeltetési kockázatot okozhat. A végleges Object Lock időtartam külön üzleti jóváhagyás.

## 6. Automatizálási runner

Elsődleges implementációs irány: GitHub Actions scheduled workflow, mert:
- a repo és CI már GitHubon van;
- a Supabase hivatalosan dokumentál CLI-alapú GitHub Actions backup mintát;
- egyszerű audit trail és futási log biztosítható.

A workflow:
- csak a jóváhagyott release/default branch verzióján fusson;
- támogassa a kézi `workflow_dispatch` tesztet;
- a négy időpontot Europe/Budapest szerint kezelje;
- ne commitolja a backupot a repóba;
- minimális GitHub permissionnel fusson;
- minden upload/ellenőrzés fail-closed legyen;
- ne logoljon connection stringet vagy secretet.

Megjegyzés: a hosted scheduler nem valós idejű hard-SLA. Ezért a backup freshness monitoringnak az elmaradt futást is észlelnie kell; önmagában a cron beállítás nem bizonyítja az RPO-t.

## 7. Retention – döntésre előkészített ajánlás

Automatikus végleges törlést a végleges jóváhagyásig nem vezetünk be.

Javasolt többgenerációs policy kiindulásnak:
- 0–14 nap: mind a napi 4 restore-pont;
- 15–90 nap: napi 1 restore-pont;
- 3–24 hónap: havi 1 restore-pont.

A B2 Object Lock minimális időtartamát úgy kell megválasztani, hogy egy hibás törlőscript vagy kompromittált credential ne tudja a rövid távú szükséges restore-pontokat eltávolítani.

A pontos retention és Object Lock napok külön üzleti döntés; addig csak létrehozás, nem automatikus törlés implementálható.

## 8. Restore runbook

A restore folyamat külön script/runbook legyen, és alapértelmezetten NEM célozhat production adatbázist.

Minimum folyamat:
1. kiválasztott backup objektum azonosítása;
2. GDrive vagy B2 letöltés;
3. titkosított artifact SHA-256 ellenőrzése;
4. `age` decrypt offline/recovery kulccsal;
5. belső `SHA256SUMS` ellenőrzése;
6. új/izolált Supabase projekt vagy sandbox előkészítése;
7. roles/schema/data visszaállítása egyértelmű hibakezeléssel és `ON_ERROR_STOP` használattal;
8. szükséges platform/Auth konfiguráció helyreállítása;
9. migration status ellenőrzése;
10. konzisztencia tesztcsomag futtatása.

### 8.1. Restore acceptance tesztek

Legalább:
- felhasználók/Auth adatok léteznek;
- profile ↔ auth user kapcsolat konzisztens;
- room és user-room jogosultságok helyesek;
- aktív/törölt booking darabszámok és kulcsmezők egyeznek;
- booking series és occurrence kapcsolatok helyesek;
- audit log rekordok megvannak és immutabilitási szabályok élnek;
- pricing konfiguráció és effective period adatok helyesek;
- havi settlement snapshot/revision adatok konzisztensen visszaálltak;
- kritikus DB függvények/triggerek/RLS szabályok jelen vannak;
- overlap/concurrency védelem regresszióteszt PASS.

A restore drill eredménye külön jegyzőkönyvbe kerül, backup timestamp + source hash + target project + teszteredmények megjelölésével.

## 9. Teljes rendszer health endpoint

Javasolt endpoint: `GET /api/health`.

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

Költségérzékeny első irány:
- UptimeRobot Free: külső HTTP/HTTPS health/uptime monitor;
- külön cron/heartbeat szolgáltatás vagy a választott monitor heartbeat funkciója a backup pipeline számára.

A végleges szolgáltató kiválasztásnál üzleti használhatóság, alert csatornák és megbízhatóság elsőbbséget élvez a kényelmi funkciókkal szemben.

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

## 13. Implementációs bontás

### Fázis A – backup mag
- backup script;
- manifest/checksum;
- `age` encryption;
- lokális/sandbox teszt.

### Fázis B – két célhely
- Google Drive upload + verify;
- B2 upload + verify;
- Object Lock konfiguráció ellenőrzés;
- részleges hibák fail-closed kezelése.

### Fázis C – scheduler/heartbeat
- GitHub Actions 08/12/16/20;
- manual run;
- heartbeat success/failure;
- missed-backup alert.

### Fázis D – restore
- restore script/runbook;
- isolated restore;
- adat- és regresszió-ellenőrzés;
- restore jegyzőkönyv.

### Fázis E – app monitoring
- `/api/health`;
- külső uptime monitor;
- alert/recovery;
- kontrollált failure drill.

### Fázis F – független review
- backup/restore stratégia;
- secret kezelés;
- Object Lock/retention;
- monitoring failure modes;
- production go/no-go checklist.

## 14. Nem része ennek a branchnek

- `main` merge;
- production deploy;
- production DB módosítása;
- production credential létrehozása vagy rotációja;
- végleges retention-törlés bevezetése jóváhagyás nélkül;
- a nyitott mobil UAT-hiba elfogadottnak minősítése.
