# UAT-bizonyítékegyeztetés – 2026-08-30

## Eredmény és döntési határ

A korábbi nyilvántartás hiányos volt: az első átvezetés **36 PASS / 59 EGYEZTETENDŐ / 3 BLOKKOLT** eredménye nem jelentett 59 el nem végzett tesztet. A projektgazda kifejezetten kérte a korábbi tesztek alapos visszakeresését és a fölösleges ismétlés elkerülését.

A helyesbített, 98 azonosítót tartalmazó [futási jegyzőkönyv](UAT_FUTASI_JEGYZOKONYV.md):

| Státusz | Darab | Értelmezés |
| --- | ---: | --- |
| SIKERES | 50 | 44 korábbi kézi/elfogadott eredmény + 6 megfelelő automatikus bizonyíték |
| MODUL-ELFOGADÁS | 22 | Korábbi elfogadott modul/UI-scope; nem minden mai összetett részlépés külön PASS |
| DÖNTÉSSEL LEZÁRT | 1 | BOOK-06; korábbi üzleti döntés, nem új kézi teszt |
| EGYEZTETENDŐ | 22 | 21 részleges bizonyíték + 1 történeti UX-státusz |
| BLOKKOLT | 3 | Production backup, restore és monitoring drill nincs igazolva |
| **Összesen** | **98** | Minden checklist-ID egyszer, duplikáció és elhagyás nélkül |

**Nem 98/98 PASS és nem 22 új kézi teszt.** Az 50 PASS a meglévő eredmények visszavezetése, nem mostani ötven tesztfutás. A PRICING/MONTH/CSV/SETTLE tesztlánc továbbra is **17/17 PASS, lezárt**.

Ebben a munkában nincs alkalmazáskód-, tesztkód-, adatbázis- vagy migrációváltozás; nincs új staging böngészős adatírás, main merge vagy production GO. Az elemzés és a dokumentációs helyesbítés nem független kódreview.

## Ellenőrzött verzió és módszer

- Repository: `ugry65/ahely-booking`; branch: `feature/82-pricing-modes`; nyitott [PR #90](https://github.com/ugry65/ahely-booking/pull/90), auto-merge nélkül.
- Ellenőrzés kiinduló HEAD: `6816c1b7260e52c12811a6ec295154c67ca5990c`. Ennek szülője az átadott alkalmazásverzió: `457363609ffac54555a7a17b1cde7742eec5b60e`.
- A 6816c1b commit csak hat Markdown-dokumentumot módosított; az alkalmazás-, migráció-, teszt- és workflow-blobok változatlanok az átadott verzióhoz képest.
- Az A-03/A-04 CI merge checkoutja `872842573afe916f80e4ef8a789695f9fe9e0e2e`; teljes path/blob fája a 6816c1b-ével egyezik.
- Main a vizsgálatkor: `9468714dbfb724d51eb1a04a1c7d79d3fa46a741`; nem célbranch.
- A staging élő migrációs HEAD-et nem kérdeztük le. A CI-ben alkalmazott migrációs sorozat nem bizonyítja önmagában a live DB azonosságát.
- Források: feltöltött átadó, beszélgetési elfogadások és visszakeresett státuszösszefoglalók; repository baseline-ok; PR #74/#76/#77/#80/#84/#89/#92 leírásai; a kapcsolódó issue/PR megjegyzések; tényleges tesztforrások és sikeres CI-logok.
- Nem tekintettük bizonyítéknak az idegen projekthez tartozó találatot, a keresési eredmény nélküli választ vagy egy PR puszta létezését.
- A dátumok a forrásban rögzített elfogadás/összefoglaló dátumai. Nem minden régi kézi teszthez ismert az eredeti pontos kattintási idő vagy teljes akkori commit.
- A régi elfogadás megmarad történeti bizonyítéknak; nem állítjuk, hogy minden korábbi UI-művelet az aktuális SHA-n újra lefutott.

A tesztelvárásokat és az elfogadásokat **szemantika szerint** párosítottuk. Egy hiányzó beszélgetésrész nem bizonyítja, hogy a teszt nem futott; egy általános „minden tesztelt dolog jó” elfogadás pedig nem bizonyítja a checklist összes negatív részlépését.

## Forráskatalógus és bizonyító erő

| Kód | Forrás | Mire használható / korlát |
| --- | --- | --- |
| H-01, M-01 | Projektgazda átadója és a folytató kézi tesztlánc; [eredeti checkpoint](UAT_CHECKPOINT_2026-08-30.md) | Eredeti 24 + 7 elfogadás, feltöltött CSV/képek. Nyers személyes adatok nem kerülnek a repositoryba |
| H-02 | [2026-08-25 infrastruktúra/funkcionális checkpoint](PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md) | TRAIN-05 korábbi elfogadása |
| R-01 | Visszakeresett 2026-08-29 13:09 UTC beszélgetési státuszösszefoglaló, továbbá az augusztus 29-i kapcsolódó kivonatok | AUTH/CAL megnevezett PASS-ok korábbi asszisztensi összesítésből, nem teljes eredeti user-kattintási napló; BOOK-09 általános említése csak részleges bizonyíték |
| R-02 | [UI/UX baseline a vizsgált headen](https://github.com/ugry65/ahely-booking/blob/6816c1b7260e52c12811a6ec295154c67ca5990c/docs/BOOKING_UI_UX_BASELINE.md), §8; [naptári műveletek](CALENDAR_BOOKING_MANAGEMENT.md) | Inaktív user és két cutoff-lemondás kifejezett történeti manuális igazolása; további UI-funkciók korábbi elfogadása |
| R-03 | [PR #74](https://github.com/ugry65/ahely-booking/pull/74), „Staging UAT – 2026-08-22”, „Current UAT status: PASS” | Onboarding/admin/import/cím/Adataim modul-scope; a külön negatív import és adószám lépések teljes kézi naplója nem áll rendelkezésre |
| R-04 | [PR #77](https://github.com/ugry65/ahely-booking/pull/77), célzott backend és végső UI-UAT | Normál user Tréningterem-repeat tiltás, admin engedés; profil-szintű repeat; SELECT-grant javítás utáni végső user-elfogadás augusztus 22-én |
| R-05 | [PR #76](https://github.com/ugry65/ahely-booking/pull/76), egységes staging UAT elfogadása | Admin, csoport/közvetlen foglalási jog, color/privacy, last-admin scope. A repeat régi részét PR #77 felülírja |
| R-06 | [Reszponzív baseline](RESPONSIVE_UI_UAT_BASELINE.md), [PR #89](https://github.com/ugry65/ahely-booking/pull/89), [helyreállítási jegyzet](reviews/RECOVERY_APPROVED_UAT_UI_2026-08-25.md) | Mobil/tablet/desktop történeti elfogadás; augusztus 24-i UI-head és három helyreállított blob. Nem külön 18:00-scroll lezárási jegyzőkönyv |
| R-07 | Visszakeresett felhasználói döntés: 2026-08-20 14:11:59 UTC; augusztus 22-i átadó | Nincs zárt nap, e pontot ne teszteljük tovább. BOOK-06 döntéssel lezárt; 017-es teszt támogatja. A 14:14:30 UTC időrács-megjegyzés nem teljes mai UI-regressziós PASS |
| R-08 | [Pénzügyi scope-döntés](DECISION_2026-08-25_FINANCIAL_SCOPE_AND_TRAINING_GROUP_RATE.md); [régi payment oldal](https://github.com/ugry65/ahely-booking/blob/6816c1b7260e52c12811a6ec295154c67ca5990c/src/app/%28protected%29/admin/befizetesek/page.tsx) | Payment UI parkoltatva; forráskódban redirect a Havi órákra; nem új élő böngészős ellenőrzés |
| A-03 | [Application #441](https://github.com/ugry65/ahely-booking/actions/runs/33316833260), [job 99271715342](https://github.com/ugry65/ahely-booking/actions/runs/33316833260/job/99271715342) | SUCCESS, 18 Vitest-fájl / 86 teszt, typecheck és build; a kiinduló 6816c1b headen |
| A-04 | [Database #411](https://github.com/ugry65/ahely-booking/actions/runs/33316833237), [job 99271715290](https://github.com/ugry65/ahely-booking/actions/runs/33316833237/job/99271715290) | SUCCESS, 46 SQL-fájl / 615 pgTAP, 7 konkurencialépés, schema lint; a kiinduló 6816c1b headen |

A magánbeszélgetéshez nem készítünk kitalált publikus permalinket. A R-01/R-07 bejegyzések a visszakeresett kivonat eredetét és korlátját írják le; valódi e-mail, token, nyers CSV vagy képernyőkép nem kerül ebbe a nyilvános repositoryba. Az A-03/A-04 a megnevezett commiton futott, nem a dokumentum későbbi commitjára előre kiadott CI-PASS.

## AUTH-azonosítók helyes párosítása

| Visszakeresett beszélgetésbeli címke | Valójában ellenőrzött működés | Checklist v1.3 |
| --- | --- | --- |
| AUTH-01 | Belépés | UAT-AUTH-01 |
| AUTH-02 | Hibás jelszó | UAT-AUTH-02 |
| AUTH-03 | Kilépés és visszairányítás | UAT-AUTH-04 |
| AUTH-04 | Jelszó-visszaállítás | UAT-AUTH-05 |
| UI/UX baseline §8, külön forrás | Inaktív user hozzáférésének tiltása | UAT-AUTH-03 |

Ez **beszélgetés és checklist közötti számozási eltérés**, nem igazolt checklist-verzióváltás. A megvizsgált régi main checklistben is az AUTH-03 az inaktív user, AUTH-04 a kijelentkezés, AUTH-05 a reset. Az inaktív tesztet nem írjuk felül kijelentkezéssel. A név szerinti történeti PASS elfogadása nem állít minden összetett alágra új, külön kattintási bizonyítékot.

CAL-03 korábbi hibája tesztidentitás/adat-előkészítési probléma volt: a valódi reset fiók örökölt jogai miatt nem volt helyes tiltott kontrollszoba. [PR #92](https://github.com/ugry65/ahely-booking/pull/92) ezt külön szintetikus USER-A-val és USER-RESET elkülönítésével rendezte; a visszakeresett összefoglaló már a javítás utáni CAL-03 PASS-t rögzíti.

## A korábban egyeztetendő 59 eset teljes feloldása

A „mostani státusz” nem új tesztfutás. A forráskódok a fenti katalógusra utalnak. A modul-elfogadásokat külön tartjuk a tételes PASS-tól.

| Teszteset | Korábbi bizonyíték osztálya | Mostani státusz | Forrás és konkrét bizonyíték |
| --- | --- | --- | --- |
| UAT-ADMIN-01 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03/R-05/M-01 — PR74/76 accepted admin/user UI; MONTH04 külön admin pénzügyi hozzáférés PASS. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ADMIN-02 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03 — PR74 admin user management/self-service onboarding UAT PASS; aktiváló link ugyanazon scope. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ADMIN-03 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-02/R-05 — PR76 user admin role/status scope accepted UAT; inaktív hozzáférés UI-baseline PASS. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ADMIN-04 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03/R-05 — PR74 katalógus explicit UAT PASS; PR76 helyiségkezelés scope accepted. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ADMIN-05 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-05 — PR76 direkt jogok megőrzés/kontroll és egységes staging UAT accepted. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ADMIN-06 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-05 — PR76 helyiségcsoport-jogok accepted UAT és effektív jog DB-tesztek. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ADMIN-07 | Elavult/ellentmondó checklist | MODUL-ELFOGADÁS | R-04/A-04 — PR #77 korábbi elfogadása; a checklist elavult per-room repeat elvárása felhasználószintű jogra helyesbítve. Nem új üzleti döntés vagy új kézi futás. |
| UAT-ADMIN-08 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-05 — PR76 globális privacy név/szín scope accepted UAT. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ADMIN-09 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-05 — PR76 last-admin review-fix, real concurrency PASS és egységes UAT elfogadva. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-AUTH-01 | Tételes korábbi elfogadás | SIKERES | R-01 — 2026-08-29 13:09 UTC beszélgetés: Belépés PASS. |
| UAT-AUTH-02 | Tételes korábbi elfogadás | SIKERES | R-01 — Ugyanott: Hibás jelszó PASS. |
| UAT-AUTH-03 | Tételes korábbi elfogadás | SIKERES | R-02 — BOOKING_UI_UX_BASELINE §8: inaktív user hozzáférésének tiltása kézzel igazolva 2026-08-20/21. |
| UAT-AUTH-04 | Tételes korábbi elfogadás | SIKERES | R-01 — 2026-08-29 összefoglaló beszélgetésbeli AUTH-03: Kilépés és visszairányítás PASS; név szerinti hozzárendelés. |
| UAT-AUTH-05 | Tételes korábbi elfogadás | SIKERES | R-01 — 2026-08-29 összefoglaló beszélgetésbeli AUTH-04: Jelszó-visszaállítás PASS; név szerinti hozzárendelés. |
| UAT-BOOK-02 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | M-01 — Szeptemberi CSV-ben 90 perces tételek és időtartam-egyezés; konkrét 10–11:30 régi lépés eredménye nem került elő. |
| UAT-BOOK-04 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-07/A-04 — 30 perces elfogadott naptári rács, 003 backend-validáció; régi 15 perces nemválasztható user-visszajelzés. |
| UAT-BOOK-05 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-02/A-04 — 07–22 UI-baseline és backend-kényszer; külön régi negatív kézi lépés nem került elő. |
| UAT-BOOK-06 | Korábban lezárt üzleti ellenőrzés | DÖNTÉSSEL LEZÁRT | R-07/A-04 — Korábbi üzleti lezárás: minden nap foglalható, további kézi tesztet a projektgazda nem kért. Nem új PASS-futtatás és nem nyitott tesztigény. |
| UAT-BOOK-09 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-01 — 2026-08-29 általános összefoglalóban érintkező foglalás PASS említve; teljes egyedi user-visszajelzés nem került elő. |
| UAT-BOOK-11 | Automatikusan igazolt | SIKERES | A-04 — 003_create_booking_rpc.sql és booking concurrency: idempotens ismétlés és mellékhatások számlálva PASS az A-04 CI-futásban. |
| UAT-CAL-01 | Tételes korábbi elfogadás | SIKERES | R-01 — 2026-08-29 13:09 összefoglaló: naptár alapbetöltés PASS. |
| UAT-CAL-02 | Tételes korábbi elfogadás | SIKERES | R-01 — Ugyanott: dátumváltás PASS. |
| UAT-CAL-03 | Tételes korábbi elfogadás | SIKERES | R-01 — Ugyanott: nem foglalható helyiség PASS javított szintetikus USER-A-val; PR92 dokumentálja az előkészítési javítást. |
| UAT-CAL-04 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-05 — PR76 egységes staging UAT accepted 2026-08-22; név/szín privacy része a scope-nak. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-CANCEL-01 | Tételes korábbi elfogadás | SIKERES | R-02 — BOOKING_UI_UX_BASELINE §8: 24 órán túli saját lemondás kézzel igazolva. |
| UAT-CANCEL-02 | Tételes korábbi elfogadás | SIKERES | R-02 — BOOKING_UI_UX_BASELINE §8: 24 órán belüli lemondás tiltása kézzel igazolva. |
| UAT-CANCEL-03 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-02/A-04 — Elfogadott három scope-os UI; 099/100 backend teszt; külön korábbi kézi occurrence-cancel napló nincs. |
| UAT-CANCEL-04 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | M-01/A-04 — MONTH02 kézi lemondás/kizárás PASS +004 admin cutoff/audit regresszió; bármikori admin törlés külön kézi napló nincs. |
| UAT-CANCEL-05 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-02/A-04 — Jóváhagyott following UI; 100 teszt kiválasztott/későbbi cancel +korábbi változatlan. |
| UAT-CANCEL-06 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-02/A-04 — Jóváhagyott series UI; 099 series cancel teszt; külön korábbi kézi napló nincs. |
| UAT-CANCEL-07 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 100 teljes scope cancel cutoff miatti rollback; külön kézi napló nincs. |
| UAT-COLOR-01 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-05 — PR76 accepted UAT; 5 profil 5 külön szín kontroll; 028 és concurrency zöld. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-EDIT-02 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 005 update RPC konfliktus és eredeti megőrzése; teljes zöld DB-csomag. |
| UAT-EDIT-03 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 005 update RPC jogosulatlan helyiség elutasítása; teljes zöld DB-csomag. |
| UAT-EDIT-04 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — Checklist 24 órás módosítási cutoffot kér; a megvizsgált 005 tesztleírásban nincs erre külön assertion; nem igazolt hiba. |
| UAT-EDIT-05 | Automatikusan igazolt | SIKERES | A-04 — test-booking-mutation-concurrency.sh: azonos verzióból két update, pontosan 1 siker, másik stale-version; mátrix szerint nem szükséges kézzel versenyeztetni. |
| UAT-EDIT-06 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-02/R-06 — CALENDAR_BOOKING_MANAGEMENT és BOOKING_UI_UX_BASELINE jóváhagyott duplikálási UI; teljes konkrét mentési napló nincs. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-IMPORT-01 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03 — PR74 tartalmazza a minimális CSV-importot és az egész flow UAT-státusza PASS. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-IMPORT-02 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03 — PR74 scope UAT PASS; ADMIN_USER_MANAGEMENT importszabályok; külön negatív import kézi napló nincs. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ONBOARD-01 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03 — PR74 UAT PASS; 016 onboarding DB-teszt; kötelező onboarding flow elfogadott scope. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ONBOARD-02 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03 — PR74 UAT PASS; responsive baseline onboarding UI; 016 magán/vállalkozói mezőellenőrzés. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-ONBOARD-03 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-03 — PR74 UAT PASS; billing-name checkbox elfogadott szerkezet; befejezés adatmodell/audit. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-PAY-01 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-08 — 2026-08-25 scope: nincs aktív payment UI; aktuális page közvetlenül /admin/havi-orak útvonalra redirectel. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-REC-02 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 009 kétheti sorozat explicit létrehozási teszt zöld; külön kézi napló nem került elő. |
| UAT-REC-04 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 009 hónapvégi havi sorozat teszt; PR84 rollbacked staging 13/14 havi sorozat kontroll PASS. |
| UAT-REC-09 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 009 őszi és tavaszi DST-falióra teszt zöld; kézi DST napló nem került elő. |
| UAT-REC-10 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-02/A-04 — Elfogadott scope-választó UI; 100 occurrence update egybookingos kontroll. |
| UAT-REC-11 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-02/A-04 — Elfogadott scope-választó UI; 099 following update teszt. |
| UAT-REC-12 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | R-02/A-04 — Elfogadott scope-választó UI; 100 series update minden aktív jövőbeli target. |
| UAT-REC-13 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 099/100 normál scope-műveletek és jogosultsági/cancel rollback részletek; az áttekintett két tesztben nem azonosítottam külön ütköző scope-update teljes rollback assertiont. A sorozatlétrehozási abort_all nem ugyanaz. |
| UAT-REC-14 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — 100 title megőrzése és speciális training rate állapotváltás; külön kézi napló nem került elő. |
| UAT-TRAIN-02 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-02 — BOOKING_UI_UX_BASELINE §4 és §8 elfogadott UI; normál szobán nincs selector, csak Tréningterem. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-TRAIN-03 | Tételes korábbi elfogadás | SIKERES | R-04 — PR77: backend UAT normál user Tréningterem-sorozat elutasítva; végső UI UAT user accepted PASS 2026-08-22. |
| UAT-TRAIN-04 | Tételes korábbi elfogadás | SIKERES | R-04 — PR77: backend UAT admin Tréningterem-sorozat engedve; végső UI UAT user accepted PASS 2026-08-22. |
| UAT-UX-01 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-02/R-06 — BOOKING_UI_UX_BASELINE mobil §2 és §8; 2026-08-21 snapshot; 2026-08-24 accepted recovery. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-UX-02 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-02/R-06 — RESPONSIVE_UI_UAT_BASELINE: tablet landscape UAT PASS, későbbi recovery accepted. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-UX-03 | Korábbi modul/UI-elfogadás | MODUL-ELFOGADÁS | R-02/R-06 — Elfogadott magyar UI-baseline és több kézi UAT; külön minden magyar stringre tételes napló nincs. Korábbi elfogadás megőrzendő; nem minden negatív/összetett részlépés külön PASS. |
| UAT-UX-04 | Részbizonyíték / egyedi napló nem került elő | EGYEZTETENDŐ | A-04 — Backend idempotencia + booking/mutation concurrency zöld; kézi dupla kattintás/lassú kérés napló nem került elő. |
| UAT-UX-05 | Ellentmondó/elavulható UX-állapot | EGYEZTETENDŐ | R-02/R-06 — Elfogadott mobil scroll baseline mellett BOOKING_UI_UX_BASELINE §9 még 18:00 körüli megakadást említ; külön végső lezárás nem került elő. |

Az eredeti 59 sor felosztása: 12 tételes történeti elfogadás + 2 automatikus igazolás + 21 korábbi modul/UI-elfogadás + 1 elavult checklist (ADMIN-07) + 1 üzleti lezárás + 21 részleges bizonyíték + 1 történeti UX-státusz = **59**. Az ADMIN-07 dokumentációs hibáját ebben a körben helyesbítettük, és a már elfogadott PR #77 modulszintű bizonyítékához rendeltük; ezért az aktuális modul-elfogadási kategória **22**, nem 21.

## Kijavított dokumentációs ellentmondások

1. **Profil-szintű repeat:** a baseline, az architektúra és az ADMIN-07 tévesen per-room/közvetlen repeat-jogot írt. A [kanonikus ismétlési szabály](RECURRING_PERMISSION_RULES.md), az [augusztus 22-i döntés](ACCESS_AND_REPEAT_DECISIONS_2026-08-22.md), PR #77, a `029_user_level_repeat_permission.sql` és a `031_repeat_legacy_rpc_contract.sql` alapján ezt helyesbítettük. Ez meglévő elfogadott szabály visszaállítása, nem új jogosultság adása.
2. **PR #77 végső UAT:** a döntési dokumentum „még szükséges” sora elavult; a PR a javítás utáni augusztus 22-i végső UI-PASS-t rögzíti. Ezt átvezettük, merge-jogosultságot nem adtunk.
3. **Múltbeli foglalás:** UI-baseline-ban az „újrateszt szükséges” szöveg elavult; BOOK-14 és REC-09A már elfogadott.
4. **Utolsó-admin konkurenciateszt:** a bizonyítékmátrix nem létező `test-last-admin-concurrency.sh` hivatkozása helyett a tényleges `scripts/test-admin-role-guard-concurrency.sh` szerepel; calendar-color és repeat concurrency is pontos fájlnévvel.
5. **Régi scroll-megjegyzés:** külön jelöltük a történeti megfigyelést és a hiányzó aktuális lezárási bizonyítékot; nem neveztük most reprodukált hibának.
6. **Státuszszinkron:** projektkontextus, checkpoint, checklist, jegyzőkönyv és readiness azonos összesítést/folytatási elvet használ; AUTH újrakezdését nem írják elő.

## Kritikus bizonyítékhatárok

| Pont | Amit a meglévő forrás ténylegesen igazol | Amit nem állítunk |
| --- | --- | --- |
| BOOK-11 | 003: azonos kulcs/payload azonos bookingot ad; booking concurrency: mindkét azonos kulcsú kérés siker, booking/audit/outbox pontosan 1/1/1 | Nem kézi dupla kattintás vagy UX-04 teljes böngészős bizonyítéka |
| EDIT-05 | Két azonos verziójú update-ből pontosan egy siker; a másik stale-version hiba; audit/outbox/ledger 1/1/1 | Nem szükséges ezt kézzel versenyeztetni |
| EDIT-04 | 005-ben sikeres update, jogosultság, időrács, konfliktus, idempotencia és partial-state kontroll | A 19 assertion között nincs külön azonosított 24 órán belüli saját update-cutoff ellenőrzés; nem állítunk implementációs hibát |
| REC-13 | 099: 16 assertion, normál scope/update/cancel kontrollok; 100: 24 assertion, normál scope, cím/díj és cancel-cutoff rollback | E két fájlban nem azonosítottunk külön ütköző scope-update összes targetjét ellenőrző rollback-assertiont. Create abort_all és cancel rollback nem ugyanaz |
| REC-09 | 009 backend DST-tesztek | MONTH-03 augusztus/szeptember hónaphatár nem kézi óraátállítási teszt |
| UX-05 | Elfogadott mobil scroll/UI-baseline, későbbi UI-helyreállítás | Nincs külön célzott végső 18:00-scroll lezárás vagy mostani reprodukció |
| Modul-UAT | PR #74/#76/#77 és UI-baseline elfogadott működés | Nem minden import-negatív, adószám-alág, jogosultsági variáció külön mai kézi PASS |
| Zöld CI | A megnevezett tesztfájlok/assertionök sikeresek a megnevezett forrásfán | Nem teljes E2E, nem live DB-migrációs azonosság és nem production GO |

Az EDIT-04/REC-13 megállapítások az átnézett konkrét tesztfájlokra korlátozódnak. Nem állítjuk teljes kódbázisvizsgálat nélkül, hogy máshol semmilyen kapcsolódó védelem vagy teszt nincs. Az üzleti szabályt nem lazítottuk az automatikus bizonyítás korlátjához.

## Folytatási szabály – fölösleges újrateszt nélkül

1. A tételes PASS, a korábbi modul-elfogadás és a BOOK-06 üzleti lezárás alapértelmezésben megőrzendő. Hiányos régi nyilvántartás nem jogosít fel automatikus újranyitásra.
2. Az EGYEZTETENDŐ soroknál előbb a konkrét assertiont, történeti elfogadást és az érintett kódváltozást kell megvizsgálni. A forráskeresés eredménytelensége önmagában nem tesztkudarc.
3. A bizonyítéknak megfelelően lehet lezárni, részlegesnek hagyni vagy konkrét pótlást javasolni. Új teszt kérésénél meg kell nevezni az ID-t, a nem igazolt elvárást, a meglévő bizonyíték határát és az ismétlés indokát.
4. Nem kezdjük újra a teljes AUTH/ONBOARD/ADMIN/UX blokkot. Nem adunk mesterséges „hátralévő kézi tesztek” darabszámot.
5. A dokumentált production kapuk külön maradnak: hosting/config és live migráció, release-releváns review, backup/off-platform példány, tényleges restore, monitoring/alert/recovery drill, majd explicit GO.
6. Ez a dokumentáció nem zárja le automatikusan #32/#82-t vagy PR #90-et, nem engedélyez main merge-et és nem módosít production állapotot.

## Dokumentációs ellenőrzési protokoll

A mentés előtti ellenőrzések eredménye: **PASS**.

- Checklist és jegyzőkönyv: ugyanaz a 98 külön ID, duplikáció/elhagyás nélkül.
- Az eredeti 59 egyeztetendő eset az auditban pontosan egyszer szerepel.
- Státuszösszeg: 50 + 22 + 1 + 22 + 3 = 98; az eredeti 36 PASS mind megmaradt; az elszámolási blokk 17/17 PASS.
- Belső Markdown-hivatkozások és az automatikus mátrixban megnevezett tesztfájlok léteznek a vizsgált repository-fában.
- A módosított aktuális jogosultsági leírások profil-szintű repeatet rögzítenek; a régi hibás mondat csak a helyesbítés magyarázataként szerepel.
- A változtatás 11 Markdown-fájlt érint; nincs alkalmazás-, teszt-, workflow- vagy migrációmódosítás. Whitespace/diff ellenőrzés hibamentes.
- A nyilvános dokumentációba személyes tesztadat, valódi e-mail, nyers CSV/kép, token vagy adatbázismentés nem került.

A GitHub-mentés után a tényleges új commitot, megváltozott fájlokat, main/PR állapotot és az új CI eredményét külön ellenőrizni kell. A jelen dokumentumban szereplő A-03/A-04 futások az ellenőrzés előtti kiinduló SHA-hoz tartoznak, így nem szükséges önhivatkozó újabb commitot készíteni pusztán az új dokumentációs SHA feltüntetéséhez.
