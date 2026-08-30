# A-Hely foglalási rendszer – UAT futási jegyzőkönyv

Checklist verzió: 1.3
Jegyzőkönyv frissítése: 2026-08-30
Kapcsolódó checklist: [Funkcionális UAT checklist](FUNKCIONALIS_UAT_CHECKLIST.md)
Kanonikus baseline: [CURRENT_FUNCTIONAL_BASELINE](CURRENT_FUNCTIONAL_BASELINE.md) v1.2
Kapcsolódó issue-k: #32, #82
Bizonyítékok és részletes korlátok: [2026-08-30-i checkpoint](UAT_CHECKPOINT_2026-08-30.md)

## Futás adatai

- Manuális eredmények: a 2026-08-29-i átadásban már elfogadott tesztek és a 2026-08-30-ig elfogadott folytatás; nem minden eset újrafuttatása ezen a napon.
- Környezet: staging, `feature/82-pricing-modes`, PR #90.
- Staging URL: https://ahely-booking-git-feature-82-pricing-modes-a-hely.vercel.app
- Átadott és elfogadott alkalmazáskód: `457363609ffac54555a7a17b1cde7742eec5b60e`.
- CI checkout: `3e33f791cf1ee526d19353ad9218848c17ba088d`; teljes fájlfa/blob-tartalom egyezik az alkalmazáskódéval.
- Adatbázis migráció HEAD: a staging élő migrációs állapota külön nem lett lekérdezve. A fenti kód CI-ben sikeresen alkalmazott legutolsó migrációja: `20260829145720_allow_past_booking_creation.sql`.
- Tesztelő / elfogadó: projektgazda; kézi végrehajtás és PASS/elfogadom visszajelzések.
- Böngésző/eszköz: Windows, Google Chrome; teljes szélesség 100% és 67% zoomon is elfogadva.
- Ez a frissítés dokumentációs átvezetés és meglévő bizonyítékok ellenőrzése; új böngészős vagy staging DB-írás nem történt.

## Összesítés

| Státusz | Esetszám | Jelentés |
| --- | ---: | --- |
| SIKERES (PASS) | 36 | 32 kézi/korábban elfogadott eset, 4 automatikus bizonyítékkal lezárt eset |
| HIBÁS | 0 | Ebben az összesítésben nincs dokumentált FAIL; nem teljes projekt-hibaleltár |
| BLOKKOLT | 3 | Backup, restore-drill, monitoring/alert drill |
| EGYEZTETENDŐ | 59 | Hiányzó vagy részleges teszteset-hozzárendelés; nem jelent bizonyítottan el nem végzett tesztet |
| NEM FUTOTT | 0 | Nem állítjuk bizonyíték nélkül, hogy egy korábbi eset nem futott |
| **Összesen** | **98** | A checklist v1.3 minden azonosítója pontosan egyszer szerepel |

**A PRICING (7), MONTH (5), CSV (3), SETTLE (2) blokk: 17/17 PASS, lezárva.** Az átadásban megjelölt hátralévő havi/CSV/settlement tesztlánc befejeződött.

Az 59 egyeztetendő sor **nem 59 automatikusan újra elvégzendő teszt**. Először a korábbi elfogadásokkal és bizonyítékokkal kell egyeztetni. Már elfogadott teszt csak új regresszió vagy releváns kódváltozás indoklásával nyitható újra.

Nyitott P1/P2/P3: az elfogadott tesztblokkban új hibát nem jelentettek; a teljes issue-állomány súlyossági felülvizsgálata nem része ennek a dokumentációs lezárásnak.

## Bizonyítékkódok

- **H-01:** a projektgazda 2026-08-29-i átadó összefoglalójában kifejezetten PASS-ként elfogadott foglalási, ismétlődési, pricing és MONTH-01 eredmények.
- **M-01:** az ezt folytató beszélgetés kifejezett PASS/elfogadom visszajelzései, a szeptemberi két CSV és képernyőképek, valamint a júliusi lezárás képei. Az átvezetés napja 2026-08-30.
- **A-01:** [Application checks #440](https://github.com/ugry65/ahely-booking/actions/runs/33267572656), 86 Vitest-teszt, typecheck és production build PASS.
- **A-02:** [Database tests #410](https://github.com/ugry65/ahely-booking/actions/runs/33267572643), 46 SQL-fájl / 615 pgTAP-ellenőrzés, 7 konkurencialépés és schema lint PASS.
- **H-02:** [2026-08-25-i elfogadott funkcionális scope](PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md), különösen Tréningterem default/override.
- **H-03:** [korábban elfogadott reszponzív UI baseline](RESPONSIVE_UI_UAT_BASELINE.md) és [2026-08-21-i státusz](STATUS_SNAPSHOT_2026-08-21_CALENDAR_UX_AND_BOOKING_ACTIONS.md). Történeti elfogadás; nem minden későbbi összetett UX-eset automatikus igazolása.

A H/M források felhasználói elfogadások; az A források automatikus ellenőrzések. Az automatikus eredmény nem kerül manuális böngészős végrehajtásként feltüntetésre.

## Teszteredmények

| Teszteset | Státusz | Megjegyzés / bizonyíték | Kapcsolódó issue |
| --- | --- | --- | --- |
| UAT-AUTH-01 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-AUTH-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-AUTH-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-AUTH-04 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-AUTH-05 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ONBOARD-01 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ONBOARD-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ONBOARD-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-IMPORT-01 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-IMPORT-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CAL-01 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CAL-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CAL-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CAL-04 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-COLOR-01 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-BOOK-01 | SIKERES | H-01 – Normál booking létrehozása. | #32 |
| UAT-BOOK-02 | EGYEZTETENDŐ | M-01: 90 perces exporttételek láthatók; a teljes előírt UI-folyamat elfogadása külön nincs hozzárendelve. | #32 |
| UAT-BOOK-03 | SIKERES | H-01 – 60 percnél rövidebb foglalás elutasítása. | #32 |
| UAT-BOOK-04 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-BOOK-05 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-BOOK-06 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-BOOK-07 | SIKERES | H-01 – Általános 90 napos előrefoglalási limit és hibaüzenet. | #32 |
| UAT-BOOK-08 | SIKERES | H-01 – Átfedés elutasítása; foglalt helyiség megfelelő hibája. | #32 |
| UAT-BOOK-09 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-BOOK-10 | SIKERES | A-02 – Két párhuzamos átfedő kérésből pontosan egy sikeres; booking/audit/outbox = 1/1/1. | #32 |
| UAT-BOOK-11 | EGYEZTETENDŐ | A-02: azonos idempotenciakulcsú konkurens kérésre 1 booking/audit/outbox; külön manuális eredmény nincs hozzárendelve. | #32 |
| UAT-BOOK-12 | SIKERES | H-01 – Sikeres mentés és hibás foglalási kísérlet megfelelő UI-visszajelzése. | #32 |
| UAT-BOOK-13 | SIKERES | H-01 – Foglalási cím mentése/megjelenése; M-01 riportbizonyíték is. | #32 |
| UAT-BOOK-14 | SIKERES | H-01 – Múltbeli egyszeri foglalás adminnal és normál userrel. | #32 |
| UAT-TRAIN-01 | SIKERES | H-01 – Tréningterem 10 napos előrefoglalási limit. | #32 |
| UAT-TRAIN-02 | EGYEZTETENDŐ | M-01-ben egyéni/csoportos tételek; a normál szobán hiányzó group selector külön nincs igazolva. | #32 |
| UAT-TRAIN-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-TRAIN-04 | EGYEZTETENDŐ | M-01-ben heti admin Tréningterem-tételek; külön teszteset-elfogadás nincs hozzárendelve. | #32 |
| UAT-TRAIN-05 | SIKERES | H-02 – 2026-08-25-én elfogadott default 5000 Ft és admin override; M-01-ben 7500 Ft-os tétel. | #32 |
| UAT-TRAIN-06 | SIKERES | A-02 – 088_atomic_training_group_rate_creation.sql: 10 ellenőrzés PASS; egyedi és sorozat rollback. | #32 |
| UAT-EDIT-01 | SIKERES | H-01 – Foglalás sikeres módosítása. | #32 |
| UAT-EDIT-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-EDIT-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-EDIT-04 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-EDIT-05 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-EDIT-06 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CANCEL-01 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CANCEL-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CANCEL-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CANCEL-04 | EGYEZTETENDŐ | MONTH-02 elfogadva; ez önmagában nem igazolja az admin bármikori lemondását és auditját. | #32 |
| UAT-CANCEL-05 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CANCEL-06 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-CANCEL-07 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-REC-01 | SIKERES | H-01 – Heti, többalkalmas sorozat; alkalomszám szerinti vég. | #32 |
| UAT-REC-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-REC-03 | SIKERES | H-01 – Napi ismétlődés. | #32 |
| UAT-REC-04 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-REC-05 | SIKERES | H-01 – Végdátum szerinti sorozatvég. | #32 |
| UAT-REC-06 | SIKERES | H-01 – Kivételdátum kihagyása és felsorolása. | #32 |
| UAT-REC-07 | SIKERES | H-01 – Ütközésnél teljes megszakítás (abort_all). | #32 |
| UAT-REC-08 | SIKERES | H-01 – Csak szabad alkalmak létrehozása; létrejött/kimaradt lista. | #32 |
| UAT-REC-09 | EGYEZTETENDŐ | MONTH-03 nem DST-váltási bizonyíték; célzott manuális eredmény külön nincs hozzárendelve. | #32 |
| UAT-REC-09A | SIKERES | H-01 – Teljesen múltbeli sorozat létrehozása és eredménye. | #32 |
| UAT-REC-10 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-REC-11 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-REC-12 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-REC-13 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-REC-14 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ADMIN-01 | EGYEZTETENDŐ | MONTH-04 havi pénzügyi menü/direct URL PASS; a teljes admin menü tesztjével nem azonos. | #32 |
| UAT-ADMIN-02 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ADMIN-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ADMIN-04 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ADMIN-05 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ADMIN-06 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ADMIN-07 | EGYEZTETENDŐ | H-01: hiányzó repeat jog hibaüzenete PASS; group-only/közvetlen jog teljes összevetése külön nincs hozzárendelve. | #32 |
| UAT-ADMIN-08 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-ADMIN-09 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-PRICING-01 | SIKERES | H-01 – 20 normál óra × 1900 Ft = 38 000 Ft. | #82 |
| UAT-PRICING-02 | SIKERES | H-01 – 15 × 2700 + 5 × 1900 = 50 000 Ft. | #82 |
| UAT-PRICING-03 | SIKERES | H-01 – Free: minden díj 0 Ft, csoportos Tréningterem is; órák megmaradnak. | #82 |
| UAT-PRICING-04 | SIKERES | H-01 – Effective month és korábbi időszak megőrzése. | #82 |
| UAT-PRICING-05 | SIKERES | H-01 – Fix admin beállítása/módosítása, effective month és előzmény. | #82 |
| UAT-PRICING-06 | SIKERES | H-01 – Fix/Free/normál díj/Tréningterem speciális díj precedenciája. | #82 |
| UAT-PRICING-07 | SIKERES | H-01 – Korábbi kezdőhónap módosítása nem törli a későbbi tervet; teljes idővonal. | #82 |
| UAT-MONTH-01 | SIKERES | H-01 – Aktív normál/csoportos órák, userenkénti díjak és havi összeg. | #82 |
| UAT-MONTH-02 | SIKERES | M-01 – Dedikált 1 órás tesztfoglalás lemondása után az órák és a fizetendő visszaálltak. | #82 |
| UAT-MONTH-03 | SIKERES | M-01 – Augusztus 31. / szeptember 1. hónaphatár, elkülönített havi összesítés; nem DST-teszt. | #82 |
| UAT-MONTH-04 | SIKERES | M-01 – Admin menü és közvetlen /admin/havi-orak URL jogosultsága; normál user elutasítva. | #82 |
| UAT-MONTH-05 | SIKERES | M-01 – Foglalás címe látható az aktív tételes listában. | #82 |
| UAT-CSV-01 | SIKERES | M-01 – Összesítő export és Excel-használhatóság elfogadva; részletes CSV-vel egyező 47 óra. | #82 |
| UAT-CSV-02 | SIKERES | A-01 – Vitest formula-injection/CSV escaping bizonyíték; felhasználó elfogadta. | #82 |
| UAT-CSV-03 | SIKERES | M-01 – Részletes CSV nyolc oszlopa között Foglalás címe; négy nem üres cím. | #82 |
| UAT-SETTLE-01 | SIKERES | M-01 – Admin UAT, 2026-07: 1 óra, 2700 Ft; lezárva, rev. 1; lezárógomb eltűnt. | #82 |
| UAT-SETTLE-02 | SIKERES | A-02 – 084_settlement_snapshot.sql: 24 ellenőrzés PASS; felhasználó elfogadta. | #82 |
| UAT-PAY-01 | EGYEZTETENDŐ | H-02: UI parkoltatott; a régi közvetlen URL elvárt átirányításának teljes UAT-ja külön nincs hozzárendelve. | #32 |
| UAT-UX-01 | EGYEZTETENDŐ | H-03: történeti mobil UX PASS; a jelen checklist teljes összetett esetének verzióhoz kötött bizonyítékát egyeztetni kell. | #32 |
| UAT-UX-02 | EGYEZTETENDŐ | H-03: történeti tablet landscape PASS; aktuális checklisthez hozzárendelés szükséges. | #32 |
| UAT-UX-03 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-UX-04 | EGYEZTETENDŐ | A rendelkezésre álló elfogadásokból nem rendelhető hozzá teljes, külön teszteset-bizonyíték. | #32 |
| UAT-UX-05 | EGYEZTETENDŐ | H-03: természetes mobil scroll elfogadva; a teljes 07–22 / 18 óra körüli regresszió külön bizonyítékát egyeztetni kell. | #32 |
| UAT-PROD-01 | BLOKKOLT | Production backup automatizálás és off-platform példány bizonyítása hiányzik. | #32 |
| UAT-PROD-02 | BLOKKOLT | Tényleges restore-drill és konzisztenciajegyzőkönyv hiányzik. | #32 |
| UAT-PROD-03 | BLOKKOLT | Production monitoring/heartbeat, alert és recovery drill bizonyítása hiányzik. | #32 |

## Kiegészítő, már elfogadott UX-eredmények

Ezek nem új checklist-azonosítók, ezért a 98 eset számlálóját nem növelik:

- Teljes fizikai oldalszélesség 100% és 67% Chrome zoomnál; admin és ismétlődő foglalási oldal is (H-01).
- Magyar hónaplista az aktuális hónaptól három évre előre; `YYYY-MM` backendérték és reszponzív ötoszlopos díjazási szerkesztősor (H-01).
- Ismétlődési jog hiányának és foglalhatósági korlátoknak megfelelő hibaüzenetek (H-01).

## Lezárt scope-döntések

| Téma | Döntés / elfogadás | Forrás |
| --- | --- | --- |
| Fix user óradíj | MEGTARTVA; admin RPC/UI és staging UAT elfogadva | PRICING-05/06, H-01 |
| Jövőbeli pricing tervek | Korábbi kezdőhónap módosítása nem törli a későbbi terveket; teljes idővonal elfogadva | PRICING-07, H-01 |
| Havi órák, CSV, snapshot | A 17 esetből álló pricing/elszámolási blokk teljesen elfogadva | H-01, M-01, A-01, A-02 |
| Sorozat-scope | occurrence/following/series üzleti szemantikája rögzített; teljes manuális scope-UAT még nem igazolt ebben a jegyzőkönyvben | SERIES_SCOPE_SEMANTICS.md, REC-10–14 |
| Régi FS v1.0 | TÖRTÉNETI / SUPERSEDED | DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md |
| Booking confirmation e-mail | Nem go-live blocker; későbbi fejlesztés | Ugyanott |
| Payment backend/UI | Backend parkoltatott; aktív UI nem scope; régi URL UAT-hozzárendelése egyeztetendő | H-02, PAY-01 |
| Heti nézet | Nem része a jelenlegi kötelező baseline-nak | CURRENT_FUNCTIONAL_BASELINE.md |

## Aktuális production kapuk

- [ ] A fennmaradó funkcionális UAT-bizonyítékok egyeztetése, majd csak a tényleges hiányok célzott tesztje; különösen AUTH/ONBOARD, jogosultságok, módosítás/lemondás és sorozat-scope.
- [ ] Production hosting/Supabase konfiguráció és migrációs/rollback terv véglegesítése.
- [ ] Production backup automatizálás és off-platform példány.
- [ ] Sikeres restore-drill, konzisztencia-ellenőrzéssel.
- [ ] Monitoring/heartbeat, tényleges alert és recovery drill.
- [ ] A végleges release-re vonatkozó kritikus független review igazolása. A korábbi Claude 6 review a saját vizsgált verzióján lezárt; a későbbi változásokra nem terjesztjük ki automatikusan.
- [ ] Explicit üzleti production GO.

## Elfogadási döntés

- [x] **Részleges funkcionális fáziszárás:** a PRICING/MONTH/CSV/SETTLE blokk teljesen elfogadva; a további bizonyított foglalási eredmények átvezetve.
- [ ] A teljes 98 esetes checklist funkcionális elfogadása igazolt.
- [ ] Production GO és main merge engedélyezve.

A projektgazda az elfogadott eredmények átvezetését, ellenőrzését és a bizonyítható pontok véglegesítését kérte. Ez nem adott main merge-, production deploy-, adatbázis-módosítási vagy automatikus issue-lezárási engedélyt. #32 és #82 nyitott státuszát ez a dokumentum nem módosítja.
