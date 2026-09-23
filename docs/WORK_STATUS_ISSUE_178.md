# Folytatási státusz — GitHub #178 admin díjszabás

Utolsó frissítés: 2026-09-23 — bizonyítékalapú LOW review-fázis lezárva
Repository: `ugry65/ahely-booking`  
Branch: `feat/178-admin-pricing`  
Base `main`: `953a233d7a1da6eafe243ed9b7e65c367c56bf3b`

## Cél

Az admin központi díjszabásának, userenkénti egyedi óradíjának és foglalásszintű óradíj-felülírásának bevezetése a meglévő pricing- és settlement-adatmodell biztonságos továbbfejlesztésével.

## Elkészült

- Külön admin `Díjszabás` oldal és navigáció.
- Központi sávok: 1–15 óra 2 500 Ft/óra; 15 óra felett–60 óráig 1 900 Ft/óra; 60 óra felett 1 700 Ft/óra.
- Tréningterem csoportos alapdíj: 5 000 Ft/óra.
- User admin adatlap `Díjazás` szakasza, időben verziózott egyedi óradíjjal.
- Admin booking létrehozás/szerkesztés díjelőnézettel, árforrással és foglalásszintű felülírással.
- Prioritás: booking override → user override → központi sáv / Tréningterem.
- Auditált pénzügyi módosítások és jogosultságvédelem.
- Settlement revision és booking line változtathatatlan snapshot; korrekció csak új, indokolt revisionként.
- AllBooked import nem hoz létre foglalásszintű ár-felülírást.
- Üzleti, adatmodell- és architektúra-dokumentáció frissítve.

## Érintett fő fájlok

- `supabase/migrations/20260922160000_admin_pricing_and_booking_rate_override.sql`
- `supabase/tests/database/111_admin_pricing.sql`
- `src/app/(protected)/admin/dijszabas/`
- `src/app/(protected)/admin/felhasznalok/`
- `src/app/(protected)/foglalasok/`
- `src/app/api/admin/pricing/quote/route.ts`
- `docs/ISSUE_178_ADMIN_PRICING_PLAN.md`

## Review-javítások állapota

- **HIGH-1 – Tréningterem 5 000 Ft/óra telepítése: LEZÁRVA a branchen.** A
  migráció a korábbi időszakot 2026-09-30-cal lezárja, 2026-10-01-től egyetlen
  5 000 Ft-os csoportos tarifát biztosít, és a változást rendszer-migrációs
  auditbejegyzéssel rögzíti. A tiszta adatbázisban szükséges Tréningterem
  rekordot a korábbi `202608220002_complete_room_catalog.sql` migráció hozza
  létre, tehát a megoldás nem függ a migrációk után futó seedtől.
- A HIGH-1 regressziós védelem három explicit pgTAP-ellenőrzést tartalmaz:
  pontosan egy aktív tarifa, a korábbi tarifa lezárási dátuma és az auditrekord
  5 000 Ft-os `after_data` értéke.
- **HIGH-2 – Settlement snapshot/revision admin integráció: LEZÁRVA a
  branchen.** A havi admin képernyő, az összesítő CSV és a tételes CSV ugyanazt
  a snapshot-aware RPC-réteget használja. A lezárt hónap legutóbbi immutable
  revisionje marad a pénzügyi képernyő és export forrása akkor is, ha az eredeti
  booking élő állapota később megváltozik.
- A HIGH-2 javítás megszüntette azt a rést, amelyben egy már snapshotolt user
  eltűnhetett az összesítőből, ha később már nem maradt aktív bookingja. Három
  új pgTAP-ellenőrzés védi a snapshot user megmaradását, a revision összegét és
  a tételes exportforrás óradíját/összegét. Három alkalmazásteszt védi a
  képernyő és a két export helyes RPC-bekötését.
- **MEDIUM M-1 – Induló központi tarifamigráció auditja: LEZÁRVA a branchen.**
  A migráció egy rendszer-eredetű, korrelációs azonosítóval és indokkal ellátott
  append-only auditbejegyzést készít. Három explicit pgTAP-ellenőrzés bizonyítja
  az audit metaadatait, a teljes korábbi 2 700/1 900/1 700 Ft-os díjsort és a
  teljes új 2 500/1 900/1 700 Ft-os díjsort. A korábbi díjsor a
  `202608160001_initial_core.sql` migrációból származik, ezért tiszta
  adatbázison sem seed-függő.
- **MEDIUM M-2 – Foglalásszintű díjindok szerkesztése: LEZÁRVA a branchen.**
  Az admin ugyanazon óradíj mellett is javíthatja a felülírás indokát; a
  változás megőrzi a régi és új indokot, az óradíjat, az actort, az időpontot
  és a correlation ID-t az auditban. Az általános booking-szerkesztés azonos
  ár és hiányzó új indok esetén kompatibilis no-op: nem törli a korábbi indokot
  és nem készít félrevezető auditot. Árváltozáskor és a felülírás
  megszüntetésekor a felület továbbra is új indokot kér.
- A többi review-megállapítás lezárása még folyamatban van; ez a státusz nem
  jelent merge- vagy production-readiness jóváhagyást.
- **LOW L-1 – User egyedi óradíj pontos webes validációja: LEZÁRVA a
  branchen.** A user egyedi óradíj mező most ugyanúgy csak nem negatív,
  JavaScriptben pontosan reprezentálható egész forintot fogad el, mint a többi
  admin pénzügyi beviteli út. A `Number.MAX_SAFE_INTEGER` fölötti érték nem
  kerülhet csendes kerekítés után a pénzügyi RPC-hez. Közvetlen unit teszt védi
  a nulla, normál, felső biztonságos határ, túl nagy, tört, negatív és üres
  bemenetet.
- Az eredeti független review fennmaradó LOW-listája nem található sem a branch
  dokumentumaiban, sem a GitHub #178 issue-ban. Emiatt a LOW tételek lezárása
  bizonyíték-alapú, önálló diff-review-val történik; találgatásból nem készül
  pénzügyi kódmódosítás.
- **LOW L-2 review-fázis – LEZÁRVA, új reprodukálható hiba nélkül.** A rögzített
  `953a233d7` base és a `9041c8bbf` branch HEAD teljes fájllistáját, valamint a
  díjszabás, user-díjazás, booking override, díjelőnézet, ismétlődő foglalás,
  havi snapshot/export és jogosultsági belépési pontok érintett kódját újra
  ellenőriztük. A review nem talált olyan új LOW hibát, amely reprodukálható
  lenne és biztonságosan indokolna pénzügyi vagy adatbázis-módosítást. Ezért
  ebben a fázisban szándékosan nem készült spekulatív kódváltozás.
- A review külön visszaellenőrizte, hogy az admin RPC-k backend oldalon is
  `require_active_admin()` ellenőrzést használnak, a SECURITY DEFINER
  függvények rögzített üres `search_path` mellett futnak, a belső pricing
  segédfüggvények végrehajtási joga vissza van vonva, és az admin végpontok
  csak az `authenticated` / `service_role` szerepköröknek vannak explicit
  engedélyezve.

## Legutóbbi ellenőrzött állapot

- Alkalmazástesztek: PASS — 31 fájl, 175 teszt.
- TypeScript typecheck: PASS.
- Next.js production build: PASS.
- SQL parser: PASS — 78 statement.
- PL/pgSQL parser: PASS — 22 függvény.
- A `111_admin_pricing.sql` SQL parser ellenőrzése: PASS — 84 statement; a
  pgTAP terv és a tényleges assertionök száma egyaránt 58.
- PostgreSQL pgTAP élő futás: helyben nem elérhető; GitHub Database tests feladata lesz.
- Független security/data-integrity review: a végső teljes diffre még kötelező; ez a LOW review nem helyettesíti.
- HIGH-1 célzott statikus ellenőrzés: PASS — 46 pgTAP assertion egyezik a
  teszttervvel. A környezetben Supabase CLI és Docker nem érhető el, ezért
  az élő pgTAP futást a későbbi GitHub Database tests fogja bizonyítani.

## Következő lépések

1. Következő fázis: végső teljes DB/alkalmazás regresszió és független
   security/data-integrity review a teljes végső diffre.
2. Review-megállapítás csak bizonyíték alapján javítható; kritikus pénzügyi,
   adatbázis- vagy security javítás után új független review szükséges.
3. PR létrehozása, GitHub Application/Database/Release/Vercel checkek ellenőrzése.
4. Merge csak review és projektgazdai jóváhagyás után.
5. Staging migráció és célzott UAT a merge után; production változtatás külön engedély nélkül tilos.

## Chat-folytatás

A Work-kredit megőrzése érdekében elkészült a teljes, önállóan használható
átadás és a bemásolható prompt:
`docs/CHAT_HANDOFF_ISSUE_178.md`. Az új beszélgetésnek a GitHub branch aktuális
HEAD-jéből és a dokumentumban felsorolt projektforrásokból kell folytatnia.

## Biztonsági korlát

Production adatbázis, konfiguráció, secret és valós production adat nem módosítható külön projektgazdai jóváhagyás nélkül.
