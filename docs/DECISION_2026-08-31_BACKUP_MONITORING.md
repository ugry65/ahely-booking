# A-Hely foglalási rendszer – Backup és production monitoring döntés

Dátum: 2026-08-31
Státusz: elfogadott architekturális döntés, production readiness követelmény.

## Backup

A production adatbázis saját, automatizált off-platform backupja kötelező.

Elfogadott ütemezés, Europe/Budapest idő szerint:
- 08:00
- 12:00
- 16:00
- 20:00

A nappali célzott backup-RPO legfeljebb kb. 4 óra. A 20:00–08:00 közötti hosszabb intervallum tudatosan elfogadott, mert ebben az időszakban várhatóan kevés változás történik. Jelentős késő esti/éjszakai aktivitás esetén az ütemezést újra kell értékelni.

Minden backup külön, időbélyegzett restore-pont legyen, ne írjon felül korábbi mentést, és integritás/checksum ellenőrzéssel készüljön.

## Két független célhely

1. Google Drive – könnyen hozzáférhető off-site példány.
2. Backblaze B2 – független második off-site példány, lehetőség szerint Object Lock / immutable védelemmel.

A Dropbox opcionális harmadik példány lehet, de nem helyettesíti a Google Drive + Backblaze B2 két független célarchitektúrát.

## Restore

Production indulás előtt kötelező tényleges restore-próba külön teszt/staging környezetbe. A restore után ellenőrizni kell legalább a foglalási, jogosultsági, audit- és elszámolási konzisztenciát. A működő backup önmagában nem elegendő; a visszaállíthatóságot bizonyítani kell.

## Production health check és monitoring

A monitoring nem csak a Supabase-re vonatkozik. A teljes production rendszer működését proaktívan kell figyelni, hogy a hibát ne a felhasználó jelezze először.

Minimum ellenőrzendő rétegek:
- publikus domain és HTTPS elérhetőség;
- hosting / Next.js alkalmazás működése;
- biztonságos health endpoint;
- Supabase / PostgreSQL elérhetőség és minimális biztonságos DB-művelet;
- válaszidő és súlyos lassulás;
- kritikus szerveroldali és szükség szerint kliensoldali hibák;
- backup heartbeat és a legutóbbi sikeres mentés ideje;
- Google Drive célra sikeres mentés;
- Backblaze B2 célra sikeres mentés és védettség;
- lehetőség szerint SSL/domain lejárat.

Az elsődleges külső uptime/health monitor lehetőség szerint ne ugyanazon hosting infrastruktúrán fusson, mint maga az alkalmazás.

Automatikus riasztás szükséges kiesés, ismételt health hiba, DB-hiba, súlyos lassulás, kritikus alkalmazáshiba és elmaradt/sikertelen backup esetén. A helyreállásról recovery értesítés is szükséges.

Production readiness során kontrollált hibával bizonyítani kell, hogy a monitor a hibát észleli, a riasztás ténylegesen megérkezik, majd a helyreállásról recovery jelzés érkezik.

## Supabase Free

A Supabase Free production használata költségoptimalizálási okból elfogadható kiindulás, amennyiben a saját backup/restore és monitoring rendszer production előtt bizonyítottan működik. Az inaktivitás miatti automatikus pause availability-kockázat, ezért a health-checknek a DB működését is ténylegesen ellenőriznie kell. Ez nem jelent rendelkezésre állási garanciát; ha a Free plan később üzemi problémát okoz, a Pro upgrade újraértékelendő.
