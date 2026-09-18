# A-Hely foglalási rendszer – UAT futási jegyzőkönyv

Checklist verzió: 1.3
Jegyzőkönyv frissítése: 2026-08-30
Kapcsolódó checklist: [Funkcionális UAT checklist](FUNKCIONALIS_UAT_CHECKLIST.md)
Kanonikus baseline: [CURRENT_FUNCTIONAL_BASELINE](CURRENT_FUNCTIONAL_BASELINE.md) v1.2
Kapcsolódó issue-k: #32, #82
Bizonyítékok és részletes korlátok: [tételes bizonyítékegyeztetés](UAT_BIZONYITEK_EGYEZTETES_2026-08-30.md) és [checkpoint](UAT_CHECKPOINT_2026-08-30.md).
A 36 PASS / 59 egyeztetendő előzetes összesítést az alábbi helyesbített nyilvántartás felülírja.

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
| SIKERES (PASS) | 50 | 44 korábbi kézi/elfogadott eredmény és 6 megfelelő automatikus bizonyíték; nem 50 új futás |
| MODUL-ELFOGADÁS | 22 | Korábban elfogadott modul/UI-scope; a teljes mai összetett eset minden részlépésére nem állítunk külön PASS-t |
| DÖNTÉSSEL LEZÁRT | 1 | BOOK-06: korábbi üzleti lezárás; nincs új kézi tesztigény |
| EGYEZTETENDŐ | 22 | 21 részleges bizonyíték és 1 történeti UX-státusz; nem bizonyítottan el nem végzett tesztek |
| BLOKKOLT | 3 | Production backup, restore és monitoring drill bizonyítéka nincs igazolva |
| HIBÁS / NEM FUTOTT | 0 / 0 | Nem minősítünk hiányos naplót hibának vagy el nem végzett tesztnek |
| **Összesen** | **98** | A checklist v1.3 minden azonosítója pontosan egyszer szerepel |

**A PRICING (7), MONTH (5), CSV (3), SETTLE (2) blokk: 17/17 PASS, lezárva.** Az átadásban megjelölt hátralévő havi/CSV/settlement tesztlánc befejeződött.

Az előzetesen egyeztetendő 59 sorból 14 további tételes PASS, 22 korábbi modul-elfogadás és 1 üzleti lezárás azonosítható. Csak 22 sor maradt részleges/tisztázandó bizonyítékú. **Ez sem 22 kötelező új kézi teszt.** A következő lépés a konkrét bizonyítékhatár szakmai tisztázása; korábbi elfogadást naplóhiány vagy pusztán új commit SHA miatt nem nyitunk újra. Újratesztet csak az érintett esethez dokumentált releváns változás/regresszió vagy ténylegesen pótlandó bizonyítás indokolhat.

Nyitott P1/P2/P3: az elfogadott tesztblokkban új hibát nem jelentettek; a teljes issue-állomány súlyossági felülvizsgálata nem része ennek a dokumentációs lezárásnak.

## Bizonyítékkódok

- **H-01:** a projektgazda 2026-08-29-i átadó összefoglalójában kifejezetten PASS-ként elfogadott foglalási, ismétlődési, pricing és MONTH-01 eredmények.
- **M-01:** az ezt folytató beszélgetés kifejezett PASS/elfogadom visszajelzései, a szeptemberi két CSV és képernyőképek, valamint a júliusi lezárás képei. Az átvezetés napja 2026-08-30.
- **A-01:** [Application checks #440](https://github.com/ugry65/ahely-booking/actions/runs/33267572656), 86 Vitest-teszt, typecheck és production build PASS.
- **A-02:** [Database tests #410](https://github.com/ugry65/ahely-booking/actions/runs/33267572643), 46 SQL-fájl / 615 pgTAP-ellenőrzés, 7 konkurencialépés és schema lint PASS.
- **H-02:** [2026-08-25-i elfogadott funkcionális scope](PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md), különösen Tréningterem default/override.
- **H-03:** [korábban elfogadott reszponzív UI baseline](RESPONSIVE_UI_UAT_BASELINE.md) és [2026-08-21-i státusz](STATUS_SNAPSHOT_2026-08-21_CALENDAR_UX_AND_BOOKING_ACTIONS.md). Történeti elfogadás; nem minden későbbi összetett UX-eset automatikus igazolása.

- **R-01:** 2026-08-29 13:09 UTC korábbi beszélgetés visszakeresett státuszösszefoglalója: AUTH és CAL PASS. Másodlagos, korábbi asszisztensi összesítés; nem teljes eredeti kattintási napló. Az AUTH számozási eltérés név szerint feloldva a tételes egyeztetésben.
- **R-02:** [UI/UX baseline §8](BOOKING_UI_UX_BASELINE.md), 2026-08-20/21 manuális elfogadások; [naptári műveletek](CALENDAR_BOOKING_MANAGEMENT.md).
- **R-03:** [PR #74](https://github.com/ugry65/ahely-booking/pull/74), 2026-08-22 modul-UAT: onboarding, user admin/import, cím és Adataim. Nem minden negatív teszt külön jegyzőkönyve.
- **R-04:** [PR #77](https://github.com/ugry65/ahely-booking/pull/77), 2026-08-22 célzott backend UAT + javítás utáni végső böngészős PASS; kanonikus user-szintű repeat.
- **R-05:** [PR #76](https://github.com/ugry65/ahely-booking/pull/76), 2026-08-22 egységes admin/jogosultság/color UAT elfogadás. A per-room repeat részét később PR #77 felülírta.
- **R-06:** [reszponzív baseline](RESPONSIVE_UI_UAT_BASELINE.md), [PR #89](https://github.com/ugry65/ahely-booking/pull/89) és [jóváhagyott UI helyreállítása](reviews/RECOVERY_APPROVED_UAT_UI_2026-08-25.md).
- **R-07:** 2026-08-20 korábbi felhasználói döntés: minden nap foglalható, ne folytassuk ennek tesztelését; visszakeresett történeti forrás és a mindennapos nyitvatartást rögzítő átadó.
- **R-08:** [2026-08-25 pénzügyi scope-döntés](DECISION_2026-08-25_FINANCIAL_SCOPE_AND_TRAINING_GROUP_RATE.md); az ellenőrzött kódban a régi payment oldal a Havi órákra irányít.
- **A-03:** [Application checks #441](https://github.com/ugry65/ahely-booking/actions/runs/33316833260), 18 fájl / 86 teszt, typecheck/build PASS, `6816c1b7260e52c12811a6ec295154c67ca5990c`.
- **A-04:** [Database tests #411](https://github.com/ugry65/ahely-booking/actions/runs/33316833237), 46 SQL-fájl / 615 pgTAP + 7 konkurencialépés + lint PASS, ugyanazon dokumentációs head. Részletes assertion-határok a tételes egyeztetésben.

A H/M források felhasználói elfogadások; az A források automatikus ellenőrzések. Az automatikus eredmény nem kerül manuális böngészős végrehajtásként feltüntetésre.

## Teszteredmények

| Teszteset | Státusz | Megjegyzés / bizonyíték | Kapcsolódó issue |
| --- | --- | --- | --- |
| UAT-AUTH-01 | SIKERES | R-01 — 2026-08-29 13:09 UTC beszélgetés: Belépés PASS. | #32 |
| UAT-AUTH-02 | SIKERES | R-01 — Ugyanott: Hibás jelszó PASS. | #32 |
| UAT-AUTH-03 | SIKERES | R-02 — BOOKING_UI_UX_BASELINE §8: inaktív user hozzáférésének tiltása kézzel igazolva 2026-08-20/21. | #32 |
| UAT-AUTH-04 | SIKERES | R-01 — 2026-08-29 összefoglaló beszélgetésbeli AUTH-03: Kilépés és visszairányítás PASS; név szerinti hozzárendelés. | #32 |
| UAT-AUTH-05 | SIKERES | R-01 — 2026-08-29 összefoglaló beszélgetésbeli AUTH-04: Jelszó-visszaállítás PASS; név szerinti hozzárendelés. | #32 |
| UAT-ONBOARD-01 | MODUL-ELFOGADÁS | R-03 — PR74 UAT PASS; 016 onboarding DB-teszt; kötelező onboarding flow elfogadott scope. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ONBOARD-02 | MODUL-ELFOGADÁS | R-03 — PR74 UAT PASS; responsive baseline onboarding UI; 016 magán/vállalkozói mezőellenőrzés. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ONBOARD-03 | MODUL-ELFOGADÁS | R-03 — PR74 UAT PASS; billing-name checkbox elfogadott szerkezet; befejezés adatmodell/audit. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-IMPORT-01 | MODUL-ELFOGADÁS | R-03 — PR74 tartalmazza a minimális CSV-importot és az egész flow UAT-státusza PASS. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-IMPORT-02 | MODUL-ELFOGADÁS | R-03 — PR74 scope UAT PASS; ADMIN_USER_MANAGEMENT importszabályok; külön negatív import kézi napló nincs. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-CAL-01 | SIKERES | R-01 — 2026-08-29 13:09 összefoglaló: naptár alapbetöltés PASS. | #32 |
| UAT-CAL-02 | SIKERES | R-01 — Ugyanott: dátumváltás PASS. | #32 |
| UAT-CAL-03 | SIKERES | R-01 — Ugyanott: nem foglalható helyiség PASS javított szintetikus USER-A-val; PR92 dokumentálja az előkészítési javítást. | #32 |
| UAT-CAL-04 | MODUL-ELFOGADÁS | R-05 — PR76 egységes staging UAT accepted 2026-08-22; név/szín privacy része a scope-nak. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-COLOR-01 | MODUL-ELFOGADÁS | R-05 — PR76 accepted UAT; 5 profil 5 külön szín kontroll; 028 és concurrency zöld. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-BOOK-01 | SIKERES | H-01 – Normál booking létrehozása. | #32 |
| UAT-BOOK-02 | EGYEZTETENDŐ | M-01 — Szeptemberi CSV-ben 90 perces tételek és időtartam-egyezés; konkrét 10–11:30 régi lépés eredménye nem került elő. | #32 |
| UAT-BOOK-03 | SIKERES | H-01 – 60 percnél rövidebb foglalás elutasítása. | #32 |
| UAT-BOOK-04 | EGYEZTETENDŐ | R-07/A-04 — 30 perces elfogadott naptári rács, 003 backend-validáció; régi 15 perces nemválasztható user-visszajelzés. | #32 |
| UAT-BOOK-05 | EGYEZTETENDŐ | R-02/A-04 — 07–22 UI-baseline és backend-kényszer; külön régi negatív kézi lépés nem került elő. | #32 |
| UAT-BOOK-06 | DÖNTÉSSEL LEZÁRT | R-07/A-04 — Korábbi üzleti lezárás: minden nap foglalható, további kézi tesztet a projektgazda nem kért. Nem új PASS-futtatás és nem nyitott tesztigény. | #32 |
| UAT-BOOK-07 | SIKERES | H-01 – Általános 90 napos előrefoglalási limit és hibaüzenet. | #32 |
| UAT-BOOK-08 | SIKERES | H-01 – Átfedés elutasítása; foglalt helyiség megfelelő hibája. | #32 |
| UAT-BOOK-09 | EGYEZTETENDŐ | R-01 — 2026-08-29 általános összefoglalóban érintkező foglalás PASS említve; teljes egyedi user-visszajelzés nem került elő. | #32 |
| UAT-BOOK-10 | SIKERES | A-02 – Két párhuzamos átfedő kérésből pontosan egy sikeres; booking/audit/outbox = 1/1/1. | #32 |
| UAT-BOOK-11 | SIKERES | A-04 — 003_create_booking_rpc.sql és booking concurrency: idempotens ismétlés és mellékhatások számlálva PASS az A-04 CI-futásban. | #32 |
| UAT-BOOK-12 | SIKERES | H-01 – Sikeres mentés és hibás foglalási kísérlet megfelelő UI-visszajelzése. | #32 |
| UAT-BOOK-13 | SIKERES | H-01 – Foglalási cím mentése/megjelenése; M-01 riportbizonyíték is. | #32 |
| UAT-BOOK-14 | SIKERES | H-01 – Múltbeli egyszeri foglalás adminnal és normál userrel. | #32 |
| UAT-TRAIN-01 | SIKERES | H-01 – Tréningterem 10 napos előrefoglalási limit. | #32 |
| UAT-TRAIN-02 | MODUL-ELFOGADÁS | R-02 — BOOKING_UI_UX_BASELINE §4 és §8 elfogadott UI; normál szobán nincs selector, csak Tréningterem. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-TRAIN-03 | SIKERES | R-04 — PR77: backend UAT normál user Tréningterem-sorozat elutasítva; végső UI UAT user accepted PASS 2026-08-22. | #32 |
| UAT-TRAIN-04 | SIKERES | R-04 — PR77: backend UAT admin Tréningterem-sorozat engedve; végső UI UAT user accepted PASS 2026-08-22. | #32 |
| UAT-TRAIN-05 | SIKERES | H-02 – 2026-08-25-én elfogadott default 5000 Ft és admin override; M-01-ben 7500 Ft-os tétel. | #32 |
| UAT-TRAIN-06 | SIKERES | A-02 – 088_atomic_training_group_rate_creation.sql: 10 ellenőrzés PASS; egyedi és sorozat rollback. | #32 |
| UAT-EDIT-01 | SIKERES | H-01 – Foglalás sikeres módosítása. | #32 |
| UAT-EDIT-02 | EGYEZTETENDŐ | A-04 — 005 update RPC konfliktus és eredeti megőrzése; teljes zöld DB-csomag. | #32 |
| UAT-EDIT-03 | EGYEZTETENDŐ | A-04 — 005 update RPC jogosulatlan helyiség elutasítása; teljes zöld DB-csomag. | #32 |
| UAT-EDIT-04 | EGYEZTETENDŐ | A-04 — Checklist 24 órás módosítási cutoffot kér; a megvizsgált 005 tesztleírásban nincs erre külön assertion; nem igazolt hiba. | #32 |
| UAT-EDIT-05 | SIKERES | A-04 — test-booking-mutation-concurrency.sh: azonos verzióból két update, pontosan 1 siker, másik stale-version; mátrix szerint nem szükséges kézzel versenyeztetni. | #32 |
| UAT-EDIT-06 | MODUL-ELFOGADÁS | R-02/R-06 — CALENDAR_BOOKING_MANAGEMENT és BOOKING_UI_UX_BASELINE jóváhagyott duplikálási UI; teljes konkrét mentési napló nincs. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-CANCEL-01 | SIKERES | R-02 — BOOKING_UI_UX_BASELINE §8: 24 órán túli saját lemondás kézzel igazolva. | #32 |
| UAT-CANCEL-02 | SIKERES | R-02 — BOOKING_UI_UX_BASELINE §8: 24 órán belüli lemondás tiltása kézzel igazolva. | #32 |
| UAT-CANCEL-03 | EGYEZTETENDŐ | R-02/A-04 — Elfogadott három scope-os UI; 099/100 backend teszt; külön korábbi kézi occurrence-cancel napló nincs. | #32 |
| UAT-CANCEL-04 | EGYEZTETENDŐ | M-01/A-04 — MONTH02 kézi lemondás/kizárás PASS +004 admin cutoff/audit regresszió; bármikori admin törlés külön kézi napló nincs. | #32 |
| UAT-CANCEL-05 | EGYEZTETENDŐ | R-02/A-04 — Jóváhagyott following UI; 100 teszt kiválasztott/későbbi cancel +korábbi változatlan. | #32 |
| UAT-CANCEL-06 | EGYEZTETENDŐ | R-02/A-04 — Jóváhagyott series UI; 099 series cancel teszt; külön korábbi kézi napló nincs. | #32 |
| UAT-CANCEL-07 | EGYEZTETENDŐ | A-04 — 100 teljes scope cancel cutoff miatti rollback; külön kézi napló nincs. | #32 |
| UAT-REC-01 | SIKERES | H-01 – Heti, többalkalmas sorozat; alkalomszám szerinti vég. | #32 |
| UAT-REC-02 | EGYEZTETENDŐ | A-04 — 009 kétheti sorozat explicit létrehozási teszt zöld; külön kézi napló nem került elő. | #32 |
| UAT-REC-03 | SIKERES | H-01 – Napi ismétlődés. | #32 |
| UAT-REC-04 | EGYEZTETENDŐ | A-04 — 009 hónapvégi havi sorozat teszt; PR84 rollbacked staging 13/14 havi sorozat kontroll PASS. | #32 |
| UAT-REC-05 | SIKERES | H-01 – Végdátum szerinti sorozatvég. | #32 |
| UAT-REC-06 | SIKERES | H-01 – Kivételdátum kihagyása és felsorolása. | #32 |
| UAT-REC-07 | SIKERES | H-01 – Ütközésnél teljes megszakítás (abort_all). | #32 |
| UAT-REC-08 | SIKERES | H-01 – Csak szabad alkalmak létrehozása; létrejött/kimaradt lista. | #32 |
| UAT-REC-09 | EGYEZTETENDŐ | A-04 — 009 őszi és tavaszi DST-falióra teszt zöld; kézi DST napló nem került elő. | #32 |
| UAT-REC-09A | SIKERES | H-01 – Teljesen múltbeli sorozat létrehozása és eredménye. | #32 |
| UAT-REC-10 | EGYEZTETENDŐ | R-02/A-04 — Elfogadott scope-választó UI; 100 occurrence update egybookingos kontroll. | #32 |
| UAT-REC-11 | EGYEZTETENDŐ | R-02/A-04 — Elfogadott scope-választó UI; 099 following update teszt. | #32 |
| UAT-REC-12 | EGYEZTETENDŐ | R-02/A-04 — Elfogadott scope-választó UI; 100 series update minden aktív jövőbeli target. | #32 |
| UAT-REC-13 | EGYEZTETENDŐ | A-04 — 099/100 normál scope-műveletek és jogosultsági/cancel rollback részletek; az áttekintett két tesztben nem azonosítottam külön ütköző scope-update teljes rollback assertiont. A sorozatlétrehozási abort_all nem ugyanaz. | #32 |
| UAT-REC-14 | EGYEZTETENDŐ | A-04 — 100 title megőrzése és speciális training rate állapotváltás; külön kézi napló nem került elő. | #32 |
| UAT-ADMIN-01 | MODUL-ELFOGADÁS | R-03/R-05/M-01 — PR74/76 accepted admin/user UI; MONTH04 külön admin pénzügyi hozzáférés PASS. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ADMIN-02 | MODUL-ELFOGADÁS | R-03 — PR74 admin user management/self-service onboarding UAT PASS; aktiváló link ugyanazon scope. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ADMIN-03 | MODUL-ELFOGADÁS | R-02/R-05 — PR76 user admin role/status scope accepted UAT; inaktív hozzáférés UI-baseline PASS. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ADMIN-04 | MODUL-ELFOGADÁS | R-03/R-05 — PR74 katalógus explicit UAT PASS; PR76 helyiségkezelés scope accepted. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ADMIN-05 | MODUL-ELFOGADÁS | R-05 — PR76 direkt jogok megőrzés/kontroll és egységes staging UAT accepted. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ADMIN-06 | MODUL-ELFOGADÁS | R-05 — PR76 helyiségcsoport-jogok accepted UAT és effektív jog DB-tesztek. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ADMIN-07 | MODUL-ELFOGADÁS | R-04/A-04 — PR #77 korábbi elfogadása; a checklist elavult per-room repeat elvárása felhasználószintű jogra helyesbítve. Nem új üzleti döntés vagy új kézi futás. | #32 |
| UAT-ADMIN-08 | MODUL-ELFOGADÁS | R-05 — PR76 globális privacy név/szín scope accepted UAT. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-ADMIN-09 | MODUL-ELFOGADÁS | R-05 — PR76 last-admin review-fix, real concurrency PASS és egységes UAT elfogadva. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
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
| UAT-PAY-01 | MODUL-ELFOGADÁS | R-08 — 2026-08-25 scope: nincs aktív payment UI; aktuális page közvetlenül /admin/havi-orak útvonalra redirectel. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-UX-01 | MODUL-ELFOGADÁS | R-02/R-06 — BOOKING_UI_UX_BASELINE mobil §2 és §8; 2026-08-21 snapshot; 2026-08-24 accepted recovery. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-UX-02 | MODUL-ELFOGADÁS | R-02/R-06 — RESPONSIVE_UI_UAT_BASELINE: tablet landscape UAT PASS, későbbi recovery accepted. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-UX-03 | MODUL-ELFOGADÁS | R-02/R-06 — Elfogadott magyar UI-baseline és több kézi UAT; külön minden magyar stringre tételes napló nincs. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. | #32 |
| UAT-UX-04 | EGYEZTETENDŐ | A-04 — Backend idempotencia + booking/mutation concurrency zöld; kézi dupla kattintás/lassú kérés napló nem került elő. | #32 |
| UAT-UX-05 | EGYEZTETENDŐ | R-02/R-06 — Elfogadott mobil scroll baseline mellett BOOKING_UI_UX_BASELINE §9 még 18:00 körüli megakadást említ; külön végső lezárás nem került elő. | #32 |
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
| Payment backend/UI | Backend parkoltatott; aktív UI nem scope; korábbi scope-elfogadás és jelen kód szerinti átirányítás igazolt, új böngészős futást nem állítunk | H-02, PAY-01 |
| Heti nézet | Nem része a jelenlegi kötelező baseline-nak | CURRENT_FUNCTIONAL_BASELINE.md |

## Aktuális production kapuk

- [ ] A 22 részleges/tisztázandó bizonyíték lezárási alapjának megállapítása. AUTH-01–05 már PASS; az elfogadott admin/onboarding/UI-modulok nem üres, újrakezdendő tesztek. EDIT/CANCEL/REC és UX esetén előbb meglévő bizonyíték/érintettség, csak utána indokolt célzott pótlás.
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
