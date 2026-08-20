# Fejlesztési szabályok

- Az FS és a projektkontextus elsődleges forrás; üzleti szabályt feltételezésből ne módosíts.
- Foglalási, pénzügyi és jogosultsági írás csak szerveroldali vagy adatbázis-függvényen keresztül történhet.
- Kritikus művelet legyen tranzakciós, auditált és idempotens.
- Foglalást, befizetést, elszámolási sort és auditrekordot alkalmazáskódból fizikailag törölni tilos.
- Minden sémaváltozás verziózott SQL-migráció.
- Ütközésvédelem kizárólag alkalmazáskódban nem elfogadható; adatbázis-kényszer kötelező.
- Kritikus üzleti logika módosításához automatikus regressziós teszt és független review szükséges.
- Secret, adatbázismentés és személyes adat nem kerülhet a repository-ba.
- A foglalási naptárt, mobil CSS-t, mobil navigációt, foglalási modált vagy saját foglalások UI-ját érintő munka előtt kötelező elolvasni a `docs/BOOKING_UI_UX_BASELINE.md` és `docs/skedda-mobile-calendar-ux.md` fájlokat.
- A `docs/BOOKING_UI_UX_BASELINE.md` dokumentumban rögzített, stagingen elfogadott működés regresszióvédett. Új fejlesztés vagy refaktor nem távolíthat el onnan funkciót, gesztust, navigációs elemet vagy mobil viselkedést külön dokumentált döntés nélkül.
- UI/UX PR esetén review során külön ellenőrizni kell a baseline regressziós checklistjét; különösen a sticky bal órasávot, mobil scroll/long-press működést, 7 napos dátumsávot, naptár ikont, `+` gyorsfoglalást, foglalási modált és mobil menü bezárását.
