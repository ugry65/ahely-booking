# A-Hely foglalási rendszer – Backup és restore stratégia

Verzió: 1.0

Dátum: 2026-08-18

Státusz: **TÖRTÉNETI BASELINE / részben SUPERSEDED**

> **Fontos 2026-09-02-i megjegyzés:** ez a dokumentum a korai backup-stratégiai kiindulópontot őrzi, de a konkrét production megoldás azóta megváltozott és tényleges restore drillel validálva lett. A backup gyakoriság, retention, célhelyek, titkosítás, artifact-formátum és restore eljárás aktuális forrásai: `docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md`, `docs/PRODUCTION_BACKUP_RESTORE_DRILL_PLAN_2026-09-01.md`, `docs/PRODUCTION_BACKUP_MONITORING_TECHNICAL_DESIGN.md`, `docs/DECISION_2026-08-31_BACKUP_RETENTION_OBJECT_LOCK.md`, valamint a `scripts/backup-production.sh` aktuális implementációja. Eltérés esetén ezek az újabb források az irányadók. A jelenlegi production backup naponta 4× fut (08/12/16/20 Europe/Budapest), Google Drive + Backblaze B2 célokra, `age` titkosítással, backupVersion 2 formátumban. A 2026-09-01-i teljes end-to-end v2 restore drill PASS.

## 1. Cél és prioritás

A foglalási adatok az A-Hely működésének és a későbbi havi elszámolásnak elsődleges forrásai. Foglalási, jogosultsági vagy elszámolási adat elvesztése nem elfogadható. A mentési rendszer célja ezért nem pusztán backup-fájlok létrehozása, hanem rendszeresen bizonyított visszaállíthatóság.

Prioritási sorrend:

1. adatmegőrzés;
2. konzisztencia;
3. visszaállíthatóság;
4. auditálhatóság;
5. jogosultságbiztonság;
6. költség és üzemeltetési egyszerűség.

## 2. Döntés: két egymástól független mentési réteg

Productionben két külön védelmi réteget használunk.

### 2.1. Menedzselt Supabase backup

Productionhöz legalább olyan Supabase csomag szükséges, amely hivatalos automatikus napi adatbázis-backupot biztosít. A 2026-08-18-i Supabase dokumentáció szerint a Pro csomag napi backupot és 7 napos retentiont ad; a Free csomagban hivatalos automatikus backup nem része a szolgáltatásnak.

A Point-in-Time Recovery (PITR) technikailag erősebb, de jelenlegi ára az A-Hely várható terheléséhez aránytalan. Ezért induláskor nem kötelező. Később külön kockázat- és költségértékeléssel bekapcsolható.

### 2.2. Elkülönített logikai off-site backup

A Supabase saját backupjától függetlenül naponta készül logikai mentés a Supabase CLI támogatott exportfolyamatával:

- `roles.sql` – adatbázis-szerepkörök;
- `schema.sql` – alkalmazási séma;
- `data.sql` – üzleti adatok;
- `manifest.json` – mentés ideje, környezet, alkalmazás commit SHA, fájlméretek és SHA-256 ellenőrzőösszegek.

A mentés nem kerülhet a Git repository-ba, GitHub Actions logba vagy alkalmazáslogba. A cél egy productiontől és Supabase-től elkülönített, titkosított objektumtár vagy más off-site tárhely.

A konkrét off-site szolgáltató külön implementációs döntés lesz. Elvárás: alacsony havi költség, titkosítás, verziózás/retention támogatás, API-alapú feltöltés, és olyan hozzáférési modell, amelyben a production alkalmazás nem tud backupot törölni.

## 3. RPO, RTO és retention

### RPO – megengedett adatvesztési ablak

Induló cél: **legfeljebb 24 óra** a napi logikai backup alapján.

A menedzselt Supabase backup ettől független második helyreállítási lehetőség. Ha a későbbi működés alapján 24 óra túl nagy üzleti kockázatnak bizonyul, a logikai backup gyakorisága növelhető vagy PITR vezethető be.

### RTO – helyreállítási cél

Induló cél: **4 órán belül legyen végrehajtható és ellenőrizhető egy adatbázis-helyreállítás** dokumentált runbook alapján, feltéve hogy a Supabase/Vercel szolgáltatások elérhetők.

Ez nem SLA, hanem belső műszaki cél, amelyet restore-drillel kell validálni.

### Retention

Induló off-site retention:

- napi backup: 35 nap;
- havi egy kijelölt backup: 13 hónap;
- törlés csak lifecycle/retention szabály alapján;
- a backup-fiókhoz és retention-beállításhoz minimális jogosultság szükséges.

Az üzleti adatmegőrzési cél továbbra is 2 év; ez nem azonos a backup-retentionnel. A hosszú távú üzleti adatoknak az elsődleges adatbázisban, auditálható módon kell megmaradniuk.

## 4. Mentési folyamat

A támogatott logikai mentési folyamat a Supabase CLI hivatalos mintáját követi.

1. Kapcsolódás production adatbázishoz read-only jellegű dump művelettel, dedikált secretből.
2. Szerepkörök exportja `--role-only` módban.
3. Séma exportja.
4. Adatok exportja `--data-only --use-copy` módban.
5. A Supabase által javasolt, nem hordozható storage vector belső táblák kizárása, ha jelen vannak.
6. SHA-256 ellenőrzőösszeg és manifest készítése.
7. Titkosított feltöltés az off-site tárhelyre.
8. Feltöltés utáni integritásellenőrzés.
9. Sikertelenség esetén a workflow hibával álljon meg; a hibát személyes adat nélkül kell jelezni.

A backup workflow soha nem írhat production üzleti táblába.

## 5. Restore runbook

Visszaállítást alapértelmezetten **nem az éles adatbázisra**, hanem külön restore/staging projektbe végzünk. Production in-place restore csak tényleges incidensnél, dokumentált döntéssel történhet.

### 5.1. Előkészítés

1. Azonosítsd a kívánt backup időpontját és manifestjét.
2. Ellenőrizd mindhárom SQL-fájl SHA-256 értékét.
3. Rögzítsd az alkalmazás commit SHA-ját és az adatbázis-migráció állapotát.
4. Hozz létre vagy jelölj ki külön Supabase restore/staging projektet production-adatok nyilvános elérése nélkül.
5. Állítsd be a szükséges extensionöket és környezeti konfigurációt.

### 5.2. Visszatöltés

A restore a Supabase támogatott sorrendjét követi:

1. `roles.sql`;
2. `schema.sql`;
3. `SET session_replication_role = replica`;
4. `data.sql`;
5. szükség esetén migrációtörténet visszatöltése;
6. Realtime publication és nem adatbázisban tárolt szolgáltatásbeállítások külön helyreállítása.

A restore során `ON_ERROR_STOP=1` és lehetőség szerint egy tranzakció használata kötelező; részlegesen sikerült restore nem tekinthető sikeresnek.

### 5.3. Kötelező restore-ellenőrzések

Restore csak akkor minősül sikeresnek, ha legalább az alábbiak igazoltak:

- alkalmazási migrációk konzisztensen jelen vannak;
- kritikus táblák és constraint-ek léteznek;
- aktív foglalások száma és mintavételes rekordjai egyeznek a backup forrásával;
- booking exclusion constraint aktív;
- RLS engedélyezve van a védett táblákon;
- `require_active_admin()` és a kritikus RPC-k elérhetők;
- auditnapló rekordjai megmaradtak;
- havi óraszám read-model fut a restaurált adatokon;
- alkalmazás smoke teszt sikeres a restore/staging környezet ellen;
- production secret vagy e-mail küldés nincs bekapcsolva a restore környezetben.

## 6. Restore-drill gyakoriság

- fejlesztési fázisban: minden backup/restore mechanizmust érintő jelentős változás után;
- production indulás előtt: kötelező teljes restore-próba;
- production üzemben: legalább negyedévente;
- minden sikertelen drillből GitHub issue készül, és a következő release előtt javítani kell a blokkoló problémát.

A drill eredménye rövid jegyzőkönyvben rögzítendő: backup azonosító, dátum, restore cél, időtartam, ellenőrzések, eltérések, döntés.

## 7. Titkok és hozzáférések

A backuphoz szükséges production adatbázis URL/jelszó és off-site tárhely credential kizárólag secret store-ban lehet.

- secret nem kerülhet repository-ba;
- secret nem jelenhet meg workflow outputban vagy logban;
- a backup credential csak olvasási/dump és feltöltési minimumjogot kapjon;
- a restore credential külön, magasabb jogosultságú és csak restore-drill/incidens során használható;
- az alkalmazás runtime service-role kulcsa nem használható backup tárhely törlésére vagy retention módosítására.

## 8. Mi nincs még implementálva ebben a baseline-ban

Ez a dokumentum a biztonsági és üzemeltetési döntést rögzíti. Külön fejlesztési szelet szükséges az alábbiakhoz:

- napi GitHub Actions vagy más scheduler alapú production dump;
- off-site tárhely konkrét kiválasztása és bekötése;
- titkosítási/kulcskezelési implementáció;
- lifecycle retention automatizálása;
- automatikus manifest és checksum ellenőrzés;
- staging/restore projekt létrehozási folyamat;
- automatikus restore-smoke teszt;
- riasztás sikertelen backup esetén.

Ezeket nem szabad élesnek tekinteni addig, amíg legalább egy teljes, dokumentált restore-drill nem sikerült.

## 9. Merge- és release-kapu

A backup/restore kritikus adatbiztonsági terület. Minden érdemi implementációhoz kötelező:

1. automatikus ellenőrzés, ahol technikailag lehetséges;
2. zöld CI ugyanazon head SHA-n;
3. független Claude code/architecture review;
4. blokkoló megállapítások javítása és célzott újra-review;
5. production bekapcsolás előtt sikeres restore-drill.

A teljes pénzügyi modul fejlesztése előtt legalább a napi off-site backup és egy sikeres restore-drill legyen kész.
