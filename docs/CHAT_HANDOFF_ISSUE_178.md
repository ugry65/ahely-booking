# Chat-átadás — GitHub #178 admin díjszabás

Átadás dátuma: 2026-09-23  
Repository: `ugry65/ahely-booking`  
Fejlesztési branch: `feat/178-admin-pricing`  
Base `main`: `953a233d7a1da6eafe243ed9b7e65c367c56bf3b`  
Utolsó, visszaellenőrzött fejlesztési checkpoint az átadás készítése előtt:
`eb6461febab013ba9ab444ec91e0328d5ecce0d8`

## Hiteles folytatási források

1. A GitHub branch aktuális HEAD-je.
2. A repository aktuális Funkcionális Specifikációja.
3. `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`.
4. `docs/ISSUE_178_ADMIN_PRICING_PLAN.md`.
5. `docs/WORK_STATUS_ISSUE_178.md`.
6. Ez az átadási dokumentum.

Ha korábbi chat és a repository között eltérés van, a repository az irányadó.

## Mi készült el

- Admin `Díjszabás` menüpont és időben verziózott központi díjsávok.
- 2026-10-01-től 2 500 / 1 900 / 1 700 Ft-os normál havi sávok.
- Tréningterem csoportos alapdíj: 5 000 Ft/óra.
- Userenkénti egyedi óradíj az admin felhasználói adatlapon.
- Booking-szintű admin óradíj-felülírás, indok és díjelőnézet.
- Prioritás: booking override → user override → központi sáv / Tréningterem.
- Auditált pénzügyi módosítások.
- Immutable settlement revision és booking-line snapshotok.
- Snapshot-aware havi admin nézet és CSV-exportok.
- AllBooked import nem hoz létre véletlen ár-felülírást.
- HIGH-1, HIGH-2, MEDIUM M-1, MEDIUM M-2 és LOW L-1 review-javítás lezárva.

A részletes bizonyítékok a `docs/WORK_STATUS_ISSUE_178.md` fájlban vannak.

## Legutóbbi ellenőrzés

- Alkalmazástesztek: PASS — 31 fájl, 175/175 teszt.
- TypeScript typecheck: PASS.
- Next.js production build: PASS.
- SQL parser: PASS — 78 statement.
- PL/pgSQL parser: PASS — 22 függvény.
- `111_admin_pricing.sql`: 84 SQL statement, 58/58 tervezett assertion.
- Élő pgTAP helyben nem futott, mert nincs Supabase CLI/Docker; ezt a GitHub
  Database testsnek kell bizonyítania.

## Mi maradt hátra

1. A teljes branch-diff újabb, bizonyíték-alapú LOW review-ja. Az eredeti
   független review LOW-listája nincs elmentve a repositoryban vagy az issue-ban,
   ezért csak konkrétan reprodukálható találat javítható; spekulatív pénzügyi
   módosítás tilos.
2. Végső teljes regresszió: alkalmazástesztek, typecheck, build, SQL/PLpgSQL
   parser és tesztterv/assertion-szám ellenőrzése.
3. Független security/data-integrity review a teljes végső diffre. A reviewernek
   külön kell vizsgálnia a jogosultságokat, auditot, történeti reprodukálhatóságot,
   snapshot-változtathatatlanságot, idempotenciát és tarifaprioritást.
4. Review-megállapítások javítása, ha vannak; utána újra teljes regresszió.
5. PR nyitása a `main` felé, majd Application checks, Database tests, Release
   evidence és Vercel checkek ellenőrzése.
6. Merge csak projektgazdai jóváhagyással.
7. Merge után külön staging DB-migráció és célzott staging UAT.
8. Production migráció vagy aktiválás csak külön, explicit projektgazdai
   jóváhagyással.

## Következő biztonságos munkafázis

Ne nyiss rögtön PR-t. Először:

1. ellenőrizd, hogy a branch HEAD tartalmazza-e ezt az átadást;
2. olvasd el a fent felsorolt hiteles forrásokat;
3. hasonlítsd össze a teljes branchet a rögzített base committal;
4. végezz egy körülhatárolt LOW review-fázist;
5. csak bizonyítható hiba esetén módosíts;
6. futtasd a releváns és teljes ellenőrzéseket;
7. frissítsd a státuszdokumentumot, commitolj és pusholj;
8. állj meg rövid státuszértékelésre.

## Biztonsági korlátok

- Közvetlenül `main`-en dolgozni tilos.
- Production DB, bookingadat, konfiguráció, secret vagy e-mail-küldés nem
  módosítható külön kifejezett jóváhagyás nélkül.
- Pénzügyi/adatbázis/security módosítás után független második review szükséges.
- GitHub írás után a tényleges commitot és fájlokat vissza kell olvasni.
- Tool-sikerüzenet önmagában nem bizonyíték.

## Bemásolható prompt új Chat beszélgetéshez

```text
Folytasd az A-Hely foglalási rendszer GitHub #178 – Admin díjszabás és
foglalásszintű óradíj-felülírás fejlesztését a GitHub repositoryból.

Repository: ugry65/ahely-booking
Branch: feat/178-admin-pricing
Rögzített base main: 953a233d7a1da6eafe243ed9b7e65c367c56bf3b

A repository main branch-e és a projektfájlok az egyetlen hiteles források.
Elsőként olvasd el teljesen:
- az aktuális Funkcionális Specifikációt;
- A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md;
- docs/ISSUE_178_ADMIN_PRICING_PLAN.md;
- docs/WORK_STATUS_ISSUE_178.md;
- docs/CHAT_HANDOFF_ISSUE_178.md.

Ellenőrizd a fejlesztési branch aktuális HEAD-jét és a teljes diffet a rögzített
base commithoz képest. Ne indulj ki korábbi chat állításaiból, ha azok nem
igazolhatók a repositoryból.

A HIGH-1, HIGH-2, MEDIUM M-1, MEDIUM M-2 és LOW L-1 javítás már elkészült.
A legutóbbi ellenőrzött állapot: 31 tesztfájl, 175/175 PASS; typecheck PASS;
Next.js production build PASS; SQL parser 78 statement; PL/pgSQL parser 22
függvény; a 111_admin_pricing.sql terve és assertionszáma 58/58. Élő pgTAP-ot
a helyi környezetben nem lehetett futtatni.

Következő feladat: egyetlen, körülhatárolt, bizonyíték-alapú LOW review-fázis.
Az eredeti független LOW-lista nincs elmentve, ezért ne találgass és ne készíts
spekulatív pénzügyi módosítást. Vizsgáld át a branch még nem lezárt részeit;
csak reprodukálható hiba esetén javíts. A javítás legyen külön kis commit,
tesztekkel. Futtasd legalább a releváns teszteket, majd a teljes tesztcsomagot,
typechecket és buildet. SQL-változás esetén futtasd a repositoryban használt
SQL/PLpgSQL parser-ellenőrzést és igazítsd a pgTAP teszteket.

A fázis végén frissítsd a docs/WORK_STATUS_ISSUE_178.md fájlt, commitolj és
pusholj a feat/178-admin-pricing branchre, majd olvasd vissza a tényleges GitHub
commitot/fájlokat. Adj rövid státuszt, és állj meg a következő fázis előtt.

Ne nyiss PR-t és ne merge-elj önállóan. Production adatbázist, production
bookingadatot, konfigurációt, secretet vagy e-mail-küldést semmilyen módon ne
módosíts külön kifejezett projektgazdai jóváhagyás nélkül. Kritikus pénzügyi,
adatbázis- vagy security változtatásnál független második review szükséges.
```
