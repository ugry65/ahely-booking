# Fejlesztési szabályok

- Az FS és a projektkontextus elsődleges forrás; üzleti szabályt feltételezésből ne módosíts.
- Foglalási, pénzügyi és jogosultsági írás csak szerveroldali vagy adatbázis-függvényen keresztül történhet.
- Kritikus művelet legyen tranzakciós, auditált és idempotens.
- Foglalást, befizetést, elszámolási sort és auditrekordot alkalmazáskódból fizikailag törölni tilos.
- Minden sémaváltozás verziózott SQL-migráció.
- Ütközésvédelem kizárólag alkalmazáskódban nem elfogadható; adatbázis-kényszer kötelező.
- Kritikus üzleti logika módosításához automatikus regressziós teszt és független review szükséges.
- Secret, adatbázismentés és személyes adat nem kerülhet a repository-ba.
