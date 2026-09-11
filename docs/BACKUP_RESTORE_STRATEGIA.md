# A-Hely foglalási rendszer – Backup és restore stratégia

Verzió: 2.0
Eredeti baseline: 2026-08-18
Frissítve: 2026-09-11
Státusz: **aktuális production baseline**

Kötelező kiegészítő döntés: `DECISION_2026-09-08_SUPABASE_FREE_AND_BACKUP_BASELINE.md`.

## 1. Cél és prioritás

A foglalási adatok az A-Hely működésének és a havi elszámolásnak elsődleges forrásai. A mentési rendszer célja több, egymástól független példány és bizonyított visszaállíthatóság.

Prioritás: adatmegőrzés, konzisztencia, visszaállíthatóság, auditálhatóság, jogosultságbiztonság, majd költség és üzemeltetési egyszerűség.

## 2. Költségbaseline és architektúra

A production Supabase környezet **Free planon** üzemel. A Supabase Pro, a menedzselt napi backup és a PITR nem production előfeltétel. A korábbi 1.0 dokumentum ezzel ellentétes mondatai superseded állapotúak.

Az elfogadott architektúra:

`Supabase Free PostgreSQL -> naponta 4x logikai backup -> titkosítás + checksum -> Google Drive + Backblaze B2 -> retention/Object Lock -> restore runbook/drill`

Az automatikus backup Europe/Budapest idő szerint 08:00, 12:00, 16:00 és 20:00 órakor esedékes. A 20:00–08:00 közötti hosszabb ablak tudatosan elfogadott kompromisszum.

## 3. Kötelező backup-tulajdonságok

- két független off-site cél: Google Drive és Backblaze B2;
- ugyanazon titkosított artifact feltöltése mindkét célra;
- roles, schema, data és Supabase migration history mentése;
- manifest és SHA-256 ellenőrzőösszeg;
- feltöltés utáni read-back/integritásellenőrzés mindkét célon;
- fail-closed működés részleges hiba esetén;
- korábbi mentések felülírásának tiltása;
- többgenerációs retention és B2 Object Lock;
- backup nem kerülhet Git repository-ba, alkalmazáslogba vagy publikus CI artifactba.

A workflow soha nem írhat production üzleti táblába.

## 4. Bizonyított állapot

A dump, titkosítás, dual-target feltöltés, read-back és checksum mechanika production kapcsolattal bizonyított. A 2026-09-01-i izolált end-to-end restore drill sikeres volt; production és staging nem került felülírásra, a recovery kulcs nem került CI-ba.

A schedule, heartbeat, least-privilege credential és aktiválási állapot külön release-hardening tételek. Ezek nem nyitják újra a Free-plan vagy a kétcélos backup architekturális döntést.

## 5. RPO, RTO és retention

- Nappali cél-RPO: körülbelül 4 óra.
- Tudatos éjszakai maximum: 12 óra 20:00 és 08:00 között.
- Belső RTO-cél: dokumentált runbook alapján 4 órán belüli, ellenőrzött helyreállítás.
- Kötelező a napon belüli, napi és havi restore-pontok többgenerációs megőrzése.
- A napi backup credential nem módosíthat Object Lock vagy retention beállítást.

## 6. Mentési folyamat

1. Kapcsolódás production adatbázishoz kizárólag dump célra, dedikált secretből.
2. Szerepkörök, séma, üzleti adatok és migrációtörténet exportja.
3. A nem hordozható belső táblák dokumentált kizárása.
4. Kontrollszámok, manifest és SHA-256 összegek készítése.
5. Titkosítás.
6. Feltöltés Google Drive-ra és Backblaze B2-re.
7. Read-back és integritásellenőrzés mindkét célon.
8. Sikerjelzés csak az összes kötelező ellenőrzés után.
9. Hiba esetén fail-closed leállás és személyes adat nélküli hibajelzés.

## 7. Restore és drill

Restore alapértelmezetten külön izolált restore/sandbox környezetbe történik. Production in-place restore csak tényleges incidensnél, explicit jóváhagyással végezhető.

Restore után ellenőrizni kell legalább a migrációs állapotot, kritikus táblákat és constraint-eket, foglalási kontrollszámokat, exclusion constraintet, RLS-t, kritikus RPC-ket, auditnaplót, havi read-modelt és alkalmazás smoke tesztet. Production e-mail és secretek restore környezetben nem lehetnek aktívak.

Teljes restore drill kötelező jelentős backup/restore változás után, production indulás előtt és rendszeresen production üzemben.

## 8. Monitoring és időzítés

Mind a négy helyi időponthoz külön heartbeat check tartozik. A scheduler futáskezdetet, lehetőség szerint explicit hibát és kizárólag dual-target siker után sikert jelez. Timeout, runnerhiba vagy olyan cancellation esetén, amikor terminális lépés már nem futhat, a hiányzó success heartbeat és a monitor grace-idő utáni riasztása a kötelező tartalék failure-path. Ismeretlen schedule, hiányzó heartbeat URL, nem HTTPS URL vagy részleges mentés hibának minősül.

A schedule kód merge-je önmagában nem aktiválhat production mentést. Az aktiválás külön, explicit jóváhagyott release-lépés, saját production Environment változóval.

Az availability/anti-pause health-check külön réteg: read-only DB ellenőrzést végez, de nem helyettesíti a backupot.

## 9. Titkok és hozzáférések

- production DB és tárhely credential csak secret store-ban lehet;
- secret nem kerülhet repository-ba vagy logba;
- napi B2 kulcs bucket-restricted és least-privilege;
- Object Lock/retention admin credential külön kezelendő;
- restore credential külön, magasabb jogosultságú és csak drill/incidens alatt használható;
- az alkalmazás runtime service-role kulcsa nem használható backup tárhelyhez.

## 10. Release-kapu

Production aktiválás előtt mind szükséges:

1. zöld CI az aktuális head SHA-n;
2. független review a kritikus backup változásokra;
3. csak `main` + `production` Environment trigger;
4. jóváhagyott schedule-aktiválás;
5. Google Drive + B2 írás és read-back bizonyíték;
6. least-privilege napi credential;
7. retention/Object Lock védelem;
8. mind a négy heartbeat alert- és recovery-próbája;
9. aktuális restore runbook és megőrzött drillbizonyíték.

Ezek teljesüléséig production GO nem adható.
