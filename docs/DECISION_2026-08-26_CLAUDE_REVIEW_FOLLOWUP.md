# A-Hely foglalási rendszer – Claude baseline review utáni döntések

Dátum: 2026-08-26
Státusz: **elfogadott üzleti döntések**

Ez a dokumentum a 2026-08-26-i független Claude-review után meghozott tulajdonosi döntéseket rögzíti. Ezek a döntések felülírják a korábbi, velük ellentétes vagy bizonytalan dokumentumértelmezést.

## 1. Fix userenkénti óradíj – MEGTARTJUK

Elfogadott döntés:
- a rendszer támogatja a `Fix óradíj` üzleti lehetőséget;
- admin userenként fix HUF/óra díjat állíthat be;
- a beállítás időbeli érvényességgel történik, a többi pricing policyhoz hasonlóan;
- a jelenlegi `user_price_overrides` DB-réteg megtartandó;
- `Free` mindig felülírja a fix díjat és 0 Ft eredményt ad;
- fix override hiányában a sávos/progresszív policy érvényesül;
- a Fix óradíj admin UI/RPC jelenleg implementációs gap, nem nyitott üzleti kérdés; production előtt rendezendő és automatikus teszttel lefedendő.

## 2. Funkcionális Specifikáció v1.0 – TÖRTÉNETI / SUPERSEDED

A régi `A-Hely_Foglalasi_Rendszer_Funkcionalis_Specifikacio_v1.0.docx` nem törlendő, de **történeti, superseded dokumentumként** kezelendő.

A jelenlegi rendszer elsődleges funkcionális forrása:
1. `docs/CURRENT_FUNCTIONAL_BASELINE.md`;
2. `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`;
3. a baseline által hivatkozott aktuális részletes döntési és UX dokumentumok.

Ha a régi FS v1.0 és a jelenlegi baseline között eltérés van, a jelenlegi baseline az irányadó, kivéve későbbi explicit üzleti döntést.

## 3. Foglalási e-mail visszaigazolás – NEM GO-LIVE BLOKKOLÓ

A foglalás létrehozásáról küldött automatikus e-mail visszaigazolás **nem kötelező az első production induláshoz**.

Az első éles verzióban elegendő, ha:
- a foglalás mentése egyértelmű UI-visszajelzést ad;
- a foglalás azonnal látszik a naptárban és a saját foglalások között;
- sikertelen mentés nem jelenhet meg sikeresként.

Az automatikus booking confirmation e-mail későbbi fejlesztési fázisba kerül. A meglévő outbox/adatmodell-előkészítés megtartható, de nem tekintendő aktív MVP production feature-nek.

## 4. Befizetések backend – PARKOLTATOTT / BEFAGYASZTOTT

A payment backend-réteg nem törlendő vissza, de **ebben a projektfázisban nem fejlesztjük tovább és nem tekintjük aktív foglalórendszer-feature-nek**.

- `Befizetések` admin UI nincs az aktív navigációban;
- a régi közvetlen oldal nem használható aktív payment UI-ként;
- a befizetések tényleges könyvelése a külön pénzügyi elszámolási projektben történik;
- a meglévő payment DB struktúra történeti/technikai tartalék, amíg külön üzleti döntés nem aktiválja újra;
- új implementációnak a jelenlegi foglalórendszer-ekvivalenciához nem kötelező payment UI-t implementálnia.

## 5. Claude review-ból következő dokumentációs feladatok

Üzleti döntés nélkül lezárandó:
- `CURRENT_FUNCTIONAL_BASELINE.md` frissítése a Fix óradíjjal és annak precedenciájával;
- régi FS superseded státuszának explicit rögzítése;
- e-mail visszaigazolás elhalasztott/nem blokkoló státuszának rögzítése;
- payment backend parkoltatott státuszának pontosítása;
- sorozat-szerkesztési/törlési scope-ok pontos dokumentálása a tényleges implementáció alapján;
- UAT checklist és futási jegyzőkönyv kiegészítése az újabb funkciókkal;
- duplikálás külön UAT-tesztesete;
- `Foglalás címe` riportkövetelmény átvezetése minden releváns dokumentumba;
- ismert mobil scroll probléma státuszának konzisztens dokumentálása.

## 6. Következő független review célja

A második Claude-review feladata nem új üzleti szabály javaslása, hanem annak ellenőrzése, hogy:
- az első review igazolt P0/P1/P2 hibái ténylegesen lezárultak-e;
- az elfogadott négy tulajdonosi döntés minden érintett dokumentumban konzisztensen szerepel-e;
- maradt-e olyan dokumentációs rés, amely miatt egy független csapat eltérő rendszert implementálhatna;
- az újraimplementálhatóság elérte-e a production-dokumentációhoz elvárt közel 100%-os szintet.
