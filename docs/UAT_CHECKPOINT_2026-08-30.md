# UAT checkpoint – 2026-08-30

Státusz helyesbítve az alapos visszakeresés után. A korábbi 36 PASS / 59 egyeztetendő előzetes összesítés nem aktuális; a részletes audit: [UAT-bizonyítékegyeztetés](UAT_BIZONYITEK_EGYEZTETES_2026-08-30.md). A már ellenőrzött CSV- és lezárási bizonyítékok változatlanok.

## Döntés és scope

A projektgazda által már elfogadott eredmények átvezetve; **a PRICING/MONTH/CSV/SETTLE blokk 17/17 PASS, lezárt**. A teljes, 98 esetes funkcionális/production checklist nem kapott blanket GO-t.

Ez dokumentációs státuszszinkronizálás, nem új üzleti döntés. Alkalmazáskód, tesztkód, SQL-migráció, adatbázisadat, main branch és production nem része a módosításnak. A korábbi eredmények visszavezetése nem új UAT-futtatás.

Elsődleges eredményforrás: [UAT futási jegyzőkönyv](UAT_FUTASI_JEGYZOKONYV.md). Az [UAT checklist v1.3](FUNKCIONALIS_UAT_CHECKLIST.md) a tesztelvárásokat tartalmazza.

## Verziók és bizonyítékhatár

| Tétel | Ellenőrzött érték / korlát |
| --- | --- |
| Repository / branch | `ugry65/ahely-booking` / `feature/82-pricing-modes` |
| PR | [#90](https://github.com/ugry65/ahely-booking/pull/90), nyitott; nincs merge-engedély |
| Elfogadott alkalmazáskód | [457363609ffac54555a7a17b1cde7742eec5b60e](https://github.com/ugry65/ahely-booking/commit/457363609ffac54555a7a17b1cde7742eec5b60e) |
| Tesztelt környezet | Staging; Windows / Chrome; a manuális képek és a projektgazda átadója szerint |
| CI checkout | `3e33f791cf1ee526d19353ad9218848c17ba088d` (PR merge ref) |
| Kódazonosság | A két verzió teljes rekurzív Git fájfájának path/blob SHA-listája egyezik |
| Staging live DB migration HEAD | Külön nem lekérdezett; nem állítunk CI-ből live migrációs azonosságot |
| CI-ben alkalmazott utolsó migráció | `20260829145720_allow_past_booking_creation.sql` |
| Main az ellenőrzéskor | `9468714dbfb724d51eb1a04a1c7d79d3fa46a741`; nem célbranch |
| Dokumentációs dátum | 2026-08-30; nem minden történeti teszt végrehajtási dátuma |

A staging URL: https://ahely-booking-git-feature-82-pricing-modes-a-hely.vercel.app

A dokumentációs commit új SHA-ja nem változtatja meg a tesztelt alkalmazáskódot. Korábbi CI-eredményt nem tüntetünk fel az új commiton frissen lefutott ellenőrzésként.

## Teljes checklist-egyeztetés

| Csoport | Összes | PASS | Modul-elfogadás | Döntéssel lezárt | Egyeztetendő | Blokkolt |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ADMIN | 9 | 0 | 9 | 0 | 0 | 0 |
| AUTH | 5 | 5 | 0 | 0 | 0 | 0 |
| BOOK | 14 | 9 | 0 | 1 | 4 | 0 |
| CAL | 4 | 3 | 1 | 0 | 0 | 0 |
| CANCEL | 7 | 2 | 0 | 0 | 5 | 0 |
| COLOR | 1 | 0 | 1 | 0 | 0 | 0 |
| CSV | 3 | 3 | 0 | 0 | 0 | 0 |
| EDIT | 6 | 2 | 1 | 0 | 3 | 0 |
| IMPORT | 2 | 0 | 2 | 0 | 0 | 0 |
| MONTH | 5 | 5 | 0 | 0 | 0 | 0 |
| ONBOARD | 3 | 0 | 3 | 0 | 0 | 0 |
| PAY | 1 | 0 | 1 | 0 | 0 | 0 |
| PRICING | 7 | 7 | 0 | 0 | 0 | 0 |
| PROD | 3 | 0 | 0 | 0 | 0 | 3 |
| REC | 15 | 7 | 0 | 0 | 8 | 0 |
| SETTLE | 2 | 2 | 0 | 0 | 0 | 0 |
| TRAIN | 6 | 5 | 1 | 0 | 0 | 0 |
| UX | 5 | 0 | 3 | 0 | 2 | 0 |
| **Összesen** | **98** | **50** | **22** | **1** | **22** | **3** |

- 24 eset a projektgazda 2026-08-29-i átadójában kifejezetten elfogadott eredményből származik (H-01).
- 7 eset az ezt követő kézi tesztlánc kifejezett PASS/elfogadom eredménye (M-01).
- 1 eset korábbi repositoryban rögzített kézi elfogadás (TRAIN-05, H-02), új havi riportmegfigyeléssel is alátámasztva.
- 4 eset automatikus bizonyítékkal lezárt: BOOK-10, TRAIN-06, CSV-02, SETTLE-02 (A-01/A-02).
- A fenti eredeti 36 PASS-hoz a visszakeresés 12 tételes történeti kézi elfogadást és 2 megfelelő automatikus eredményt rendelt: összesen 50 PASS (44 kézi/korábban elfogadott, 6 automatikus).
- További 22 korábbi modul-elfogadás és 1 üzleti lezárás külön státuszú; a fennmaradó 22 részleges/tisztázandó bizonyíték nem új kéziteszt-darabszám.
- Nincs ebben az átvezetésben dokumentált FAIL. Ez nem a teljes nyitott issue-lista hibamentességi nyilatkozata.

A régi jegyzőkönyv 1.2-es verziójelzését 1.3-ra igazítottuk; a hiányzó **BOOK-14** és **REC-09A** sor bekerült. A már elfogadott múltbeli egyszeri/sorozatos foglalást nem nyitottuk újra.

## Manuális bizonyíték és CSV-egyeztetés

A H-01 forrás a projektgazda átadó összefoglalója; a M-01 forrás az ezt folytató beszélgetés és a feltöltött képek/CSV-k. A pontos előzménybeli kattintási napló és külön végrehajtási időpont nem minden teszthez áll rendelkezésre. A felhasználói elfogadást ettől nem írjuk át NEM FUTOTT-ra.

### Szeptemberi exportok

| Fájl | SHA-256 |
| --- | --- |
| `a-hely-havi-orak-2026-09.csv` | `0c3b1619ac6b59a97b07f8b5b7efb20c7986d9fee336e071314a956cee4c59d7` |
| `a-hely-havi-orak-reszletes-2026-09.csv` | `09b36cc4d5d178fe493c477426d2f45ff795e1a8608c99f5edb2dc3c23716870` |

Ellenőrzött, személyazonosítás nélküli összesítés:

- Összesítő: 3 felhasználói sor, összesen **47 óra**.
- Részletes: **46 tétel**, összesen **47 óra**; felhasználónként egyezik az összesítővel.
- A három felhasználó óraszáma 12, 15 és 20; az elsőhöz 12, a másodikhoz 15, a harmadikhoz 19 tétel tartozik.
- Minden tétel szeptemberi; az óraszám minden sorban megegyezik a kezdés/vég különbségével; teljes sor szerinti duplikátum nincs.
- UTF-8 BOM, CRLF, pontosvesszős elválasztás, tizedesvessző; magyar ékezetek és fájlnév rendben.
- Részletes export: 8 oszlop, köztük `Foglalás címe`; 4 nem üres cím.
- A pénzügyi képernyőn az admin tesztuser 11 normál + 1 csoportos órája összesen 12 óra; 29 700 + 7 500 = 37 200 Ft.
- A másik két sor fizetendője 40 500 Ft és 0 Ft; a kijelölt hónap összesen **77 700 Ft**. A Free felhasználó 20 órája a nulla díj ellenére megmarad.

A fájlok a felhasználó csatolmányai; a nyers CSV-ket és képernyőképeket személyes adataik miatt **nem másoljuk a repositoryba**. A checksum az ellenőrzött példányt azonosítja, nem helyettesíti a felhasználó birtokában maradó bizonyítékot. A konkrét előírt tesztcím megjelenését nem állítjuk olyan exportból, amely más, már meglévő foglalási címeket tartalmaz.

### Hónaplezárás

- Tesztuser: Admin UAT; hónap: **2026-07**.
- Lezárás előtt: 1 normál óra, Sávos, 2700 Ft, „Lezárható”, megerősítő párbeszéd.
- Lezárás után: változatlan 1 óra / 2700 Ft; „Lezárva”, **rev. 1**, a képernyőn **2026. aug. 30. 16:04**; lezárógomb helyett nincs új lezárási művelet.
- A projektgazda a lezárási eredményt elfogadta. A „Lezárva” a pénzügyi snapshot rögzítését jelenti, **nem kifizetettséget**. A „rev. 1” az első rögzített verzió száma.
- A SETTLE-02 eredménye automatikus CI-bizonyíték; nem kíséreltünk meg lezárt staging adatsort közvetlenül módosítani.

### Teszthatárok

A MONTH-03 augusztus/szeptember hónaphatári elfogadás nem bizonyítja önmagában a REC-09 DST-váltást. A MONTH-04 admin-only havi nézet nem a teljes AUTH/ADMIN jogosultsági mátrix tesztje. A MONTH-02 elszámolásból kizárás nem a teljes CANCEL audit/cutoff/scope mátrix elfogadása.

## Automatikus bizonyíték

Az A-01/A-02 az alkalmazáskód eredeti CI-bizonyítéka. A későbbi, csak dokumentációt módosító `6816c1b7260e52c12811a6ec295154c67ca5990c` headen az [Application #441](https://github.com/ugry65/ahely-booking/actions/runs/33316833260) és [Database #411](https://github.com/ugry65/ahely-booking/actions/runs/33316833237) is SUCCESS: 86 alkalmazásteszt és 615 pgTAP, 7 konkurencialépés, typecheck/build/lint. A-03/A-04 néven ezek támasztják alá a most visszavezetett automatikus eredményeket. A dokumentáció későbbi commitjára új CI-t nem állítunk előre.

### A-01 – Application checks

[Run #440 / 33267572656](https://github.com/ugry65/ahely-booking/actions/runs/33267572656) · [job 99140265978](https://github.com/ugry65/ahely-booking/actions/runs/33267572656/job/99140265978) · 2026-08-29 · **SUCCESS**.

- 18 Vitest-fájl / **86 teszt PASS**, typecheck és Next.js production build PASS.
- A `src/lib/monthly-hours.test.ts` 7 tesztje között formula-injection/escaping védelem, exportformátum és részletes címmező.
- A konkrét formulaesetek között `=1+1` és kezdő whitespace utáni `-2+3` semlegesítése; idézőjelek escape-elése.
- A kód whitespace utáni `= + - @` kezdetet véd; nem állítjuk, hogy minden prefixhez külön Excel-interakciós teszt futott.
- CSV-02: a felhasználó az automatikus bizonyítékot elfogadta.

### A-02 – Database tests

[Run #410 / 33267572643](https://github.com/ugry65/ahely-booking/actions/runs/33267572643) · [job 99140266097](https://github.com/ugry65/ahely-booking/actions/runs/33267572643/job/99140266097) · 2026-08-29 · **SUCCESS**.

- **46 SQL-fájl / 615 pgTAP-ellenőrzés PASS**, schema lint PASS.
- 7 sikeres konkurencialépés: booking creation, booking mutation, room access, recurring booking, last-admin guard, calendar color, repeat permission.
- BOOK-10: `scripts/test-booking-concurrency.sh` két átfedő párhuzamos kérésből pontosan egy sikert és 1 booking / 1 audit / 1 outbox rekordot ellenőriz; magyar üzleti hibával.
- TRAIN-06: `088_atomic_training_group_rate_creation.sql`, **10 ellenőrzés**; egyedi booking és sorozat egyedi díja, admin-only út, audit és díjrögzítési hiba utáni rollback.
- SETTLE-02: `084_settlement_snapshot.sql`, **24 ellenőrzés**; admin-only lezárás, központi pricinggel egyező snapshot, ismételt lezárás tiltása, revision/booking-line változtathatatlanság, append-INSERT tiltás, lezárási metaadatok védelme és audit.
- A privilegizált módosítási próbák is CI-tesztadatbázisban történtek. A pgTAP-fájlok tranzakció/rollback környezetűek; nem a staging adatokat módosítják.
- SETTLE-02: a felhasználó az automatikus bizonyítékot elfogadta.

A zöld teljes csomag nem helyettesíti az összes manuális, jogosultsági és UX-teszteset bizonyíték-hozzárendelését.

## Független review – mi zárt és mi nem

A [Claude 6 végső closure](CLAUDE_REVIEW_6_FINAL_CLOSURE_STATUS.md) a **PR #91**, `63748919aaa0c2458277536643f79b37efd0bf7c` állapotra dokumentált lezárás: nincs P0/P1/MEDIUM+ closure blocker, implementáció kész, UAT-ra kész. A settlement append-mutation védelem is ennek része.

Ez **repositoryban rögzített független review-eredmény**, nem újonnan adott GitHub PR-approval. A mostani ellenőrzés nem új független kritikus review.

A review-verzióhoz képest az elfogadott alkalmazásverzió 14 commitot és 28 módosult fájlt tartalmaz; többek között UAT-előkészítési, ismétlődési UI-, oldalszélesség-, hónapválasztó- és múltbeli foglalási változásokat. A korábbi closure-t nem terjesztjük ki automatikusan ezekre. A végleges release releváns változásaira és production infrastruktúrájára külön review-bizonyíték szükséges.

## Mi maradt nyitva, és hogyan folytassuk

1. **Az 59 sor első egyeztetése elkészült:** 14 további PASS, 22 korábbi modul-elfogadás, 1 üzleti lezárás és 22 részleges/tisztázandó bizonyíték. AUTH-01–05 már PASS, az admin/onboarding/UI elfogadásokat nem kérjük újra.
2. **Célzott bizonyítéktisztázás:** a 22 részleges sor meglévő assertionjeinek, történeti forrásainak és releváns változásainak értékelése; különösen EDIT-04, REC-13 és UX-05. Hiányzó kattintási napló önmagában nem bizonyított el nem végzett teszt. Új kézi teszt csak konkrétan indokolt réshez kérhető; darabszáma ebből az állapotból nem állapítható meg.
3. **Review és konfiguráció:** végleges release, hosting/Supabase beállítások, live migrációs állapot, migrációs/rollback terv igazolása.
4. **Production adatbiztonság:** backup/off-platform példány, tényleges restore-drill, konzisztenciaellenőrzés; PROD-01/02 továbbra is BLOKKOLT.
5. **Production monitoring:** heartbeat, alert és recovery drill; PROD-03 továbbra is BLOKKOLT.
6. **Külön jóváhagyás:** teljes funkcionális elfogadás és explicit production GO után lehet main merge-/élesítési döntést hozni. Ez a checkpoint ilyen engedélyt nem ad.

A #32 teljes funkcionális UAT issue és a #82 feature issue nyitva marad; ez a dokumentációs átvezetés nem zárja le a teljes projektet vagy a PR-t.
