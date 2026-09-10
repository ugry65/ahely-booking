# A-Hely foglalási rendszer – Backup és restore stratégia

Verzió: 2.0

Eredeti baseline: 2026-08-18
Frissítve: 2026-09-08

Státusz: **aktuális production baseline**

Kötelező kiegészítő döntés: `DECISION_2026-09-08_SUPABASE_FREE_AND_BACKUP_BASELINE.md`.

## 1. Cél és prioritás

A foglalási adatok az A-Hely működésének és a havi elszámolásnak elsődleges forrásai. Foglalási, jogosultsági vagy elszámolási adat elvesztése nem elfogadható. A mentési rendszer célja nem pusztán backup-fájlok létrehozása, hanem több, egymástól független példány és bizonyított visszaállíthatóság.

Prioritási sorrend:

1. adatmegőrzés;
2. konzisztencia;
3. visszaállíthatóság;
4. auditálhatóság;
5. jogosultságbiztonság;
6. költség és üzemeltetési egyszerűség.

## 2. Költségbaseline: Supabase Free

A production Supabase környezet **Free planon** készül és üzemel. A Supabase Pro, a menedzselt napi backup és a PITR **nem production előfeltétel és nem kötelező release-gate**.

A korábbi 1.0 dokumentum azon mondata, amely szerint productionhöz legalább automatikus menedzselt Supabase backupot adó csomag szükséges, **SUPERSEDED**.

Az adatbiztonságot a saját, kétcélos, ellenőrzött backup/restore rendszer biztosítja. A Pro/PITR későbbi opcionális upgrade lehet, de erre a rendszer biztonságos működése nem épülhet.

## 3. Elfogadott kétcélos backup architektúra

A production PostgreSQL logikai backupja automatikusan, naponta négyszer készül, Europe/Budapest idő szerint:

- 08:00;
- 12:00;
- 16:00;
- 20:00.

Két egymástól független off-site cél kötelező:

1. **Google Drive** – könnyen elérhető első off-site példány;
2. **Backblaze B2** – szolgáltatói szinten független második példány, Object Lock / törlés elleni védelemmel.

A backup-rendszer alapelvei:

- önálló, időbélyegzett restore-pontok;
- korábbi mentés nem írható felül;
- konzisztens PostgreSQL logikai dump;
- titkosított kezelés;
- manifest + SHA-256 ellenőrzőösszeg;
- feltöltés utáni read-back/integritásellenőrzés mindkét célon;
- fail-closed működés részleges feltöltési hiba esetén;
- többgenerációs retention;
- Backblaze B2 Object Lock;
- backup nem kerülhet Git repository-ba, alkalmazáslogba vagy publikus artifactba.

## 4. Bizonyított állapot

A backup/restore architektúra és a kétcélos integritási mechanika implementálása és tesztelése megtörtént.

Bizonyított eredmények:

- dual-target integrity: checksum + read-back mindkét célon működik;
- health endpoint: valódi read-only DB-ellenőrzés, információszivárgás nélkül;
- 2026-09-01-i izolált end-to-end restore-drill sikeres volt;
- a restore során production és staging környezet nem került felülírásra;
- a recovery kulcs nem került CI-ba;
- a restore-folyamat a korábbi hibát feltárta, majd a javított v2 formátummal bizonyítottan végrehajthatóvá vált.

A korábbi független review release-hardening megállapításai (workflow trigger, least-privilege credential, merge/aktiválási státusz, retention scheduling, monitoring alert/recovery drill) külön üzemeltetési/release tételek. Ezek **nem nyitják újra** a Free-plan vagy a kétcélos backup architekturális döntést.

## 5. RPO, RTO és retention

### RPO

A napi négyszeri ütemezés nappal kb. 4 órás backup-RPO-t céloz. A 20:00–08:00 közötti hosszabb éjszakai intervallum tudatosan elfogadott kompromisszum, amelyet a tényleges használati adatok alapján később felül kell vizsgálni, ha éjszakai aktivitás érdemben nő.

### RTO

Belső műszaki cél: dokumentált runbook alapján 4 órán belül végrehajtható és ellenőrizhető helyreállítás, feltéve hogy a szükséges platformok elérhetők.

### Retention

Kötelező többgenerációs megőrzés:

- rövid távon a napon belüli restore-pontok;
- hosszabb távú napi és havi restore-pontok;
- B2 oldalon megfelelő Object Lock időtartam;
- lifecycle/retention szabály alapú törlés;
- production alkalmazás ne tudja a backup retentiont gyengíteni vagy a teljes mentési készletet törölni.

## 6. Mentési folyamat

1. Kapcsolódás production adatbázishoz kizárólag dump célra, dedikált secretből.
2. Szerepkörök exportja.
3. Séma exportja.
4. Üzleti adatok exportja.
5. Nem hordozható belső táblák dokumentált kizárása, ahol szükséges.
6. Manifest és SHA-256 ellenőrzőösszegek készítése.
7. Titkosítás.
8. Feltöltés Google Drive célra.
9. Feltöltés Backblaze B2 célra.
10. Read-back és integritásellenőrzés mindkét célon.
11. Siker csak akkor, ha minden kötelező lépés igazolt.
12. Hiba esetén fail-closed leállás és személyes adat nélküli hibajelzés.

A backup workflow soha nem írhat production üzleti táblába.

## 7. Restore runbook

Restore alapértelmezetten **nem az éles adatbázisra**, hanem külön izolált restore/sandbox környezetbe történik. Production in-place restore kizárólag tényleges incidensnél, explicit jóváhagyással végezhető.

Kötelező ellenőrzések restore után:

- migrációs állapot konzisztens;
- kritikus táblák, constraint-ek és triggerek léteznek;
- foglalási adatok és mintavételes rekordok egyeznek;
- booking exclusion constraint aktív;
- RLS engedélyezve van;
- kritikus RPC-k elérhetők;
- auditnapló megmaradt;
- havi read-model működik;
- alkalmazás smoke teszt sikeres;
- restore környezetben production e-mail/secrets nincsenek aktív állapotban.

## 8. Restore-drill gyakoriság

- backup/restore mechanizmust érintő jelentős változás után;
- production indulás előtt kötelező teljes restore-próba;
- production üzemben rendszeres, dokumentált restore-drill;
- sikertelen drillből javítási feladat készül és blokkoló hiba production release előtt lezárandó.

A 2026-09-01-i első izolált end-to-end restore-drill megtörtént és sikeres volt.

## 9. Titkok és hozzáférések

- production DB credential és backup tárhely credential csak secret store-ban lehet;
- secret nem kerülhet repository-ba vagy logba;
- napi backup kulcsok least-privilege elvűek;
- Object Lock/retention konfigurációhoz szükséges emelt jogosultság külön kezelendő;
- restore credential külön, magasabb jogosultságú és csak drill/incidens során használható;
- alkalmazás runtime service-role kulcsa nem használható backup tárhely törlésére vagy retention módosítására.

## 10. Supabase Free automatikus pause

Az inaktivitás miatti Supabase Free pause availability-kockázat, **nem backup-probléma**.

Külön production health-check szükséges, amely rendszeresen valódi, biztonságos, read-only DB lekérdezést hajt végre. Ez egyszerre ellenőrzi a Supabase/PostgreSQL elérhetőséget és legitim adatbázis-aktivitást biztosít.

A health-check nem módosíthat üzleti adatot és nem helyettesíti a backup/restore rendszert.

## 11. Release-kapu

A backup/restore architektúrát nem kell újratervezni és nem kell Supabase Pro-val kiváltani.

Production bekapcsolás előtt a tényleges üzemeltetési láncban ellenőrizendő:

1. ütemezett backup workflow aktív a megfelelő branch/environment környezetben;
2. production secretek csak biztonságos triggerből érhetők el;
3. napi backup credential least-privilege;
4. Google Drive + Backblaze B2 írás és read-back működik;
5. retention/Object Lock védelmek aktívak;
6. monitoring/heartbeat és alert/recovery teszt működik;
7. restore runbook aktuális és a drill bizonyíték megőrzött.

Ezek release-hardening ellenőrzések, nem új architekturális vagy előfizetési döntések.
