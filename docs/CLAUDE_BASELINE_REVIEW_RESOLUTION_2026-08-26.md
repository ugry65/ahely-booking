# Claude független baseline-review – feldolgozási jegyzőkönyv

Dátum: 2026-08-26
Vizsgált baseline: `docs/CURRENT_FUNCTIONAL_BASELINE.md`
Független reviewer: Claude
Feldolgozás: ChatGPT/Work a repository tényleges kódjával és projektforrásaival összevetve.

## Összegzés

Claude végkövetkeztetése: `IGEN, DE HIÁNYOSSÁGOKKAL`, 82%-os dokumentációs újraimplementálhatósági értékeléssel.

A review lényegi pozitív megállapítása elfogadva: a kritikus foglalási, konkurencia-, jogosultsági, tiered/progressive/free, Tréningterem, audit- és settlement invariánsok nagy része egyezik a tényleges implementációval és tesztekkel.

A review megállapításait nem automatikusan fogadtuk el; az alábbi státuszok repository-ellenőrzésen alapulnak.

## P0-1 – `user_price_overrides` fix user óradíj

**Státusz: IGAZOLT, üzleti döntés szükséges.**

A `calculate_monthly_pricing` jelenlegi implementációja ténylegesen lekérdezi a `user_price_overrides` táblát. Érvényes override esetén:
- normál órák díja fix user óradíj alapján számolódik;
- ez felülírja a `tiered` és `progressive` számítást;
- `free` pricing policy esetén továbbra is 0 Ft az eredmény.

A `user_price_overrides` már az induló core adatmodell része volt, tehát nem véletlen új tábla.

Ugyanakkor a jelenlegi feature branchben nincs kész, elfogadott admin UI/RPC ennek napi kezelésére. Ezért nem lehet sem eltávolítható legacy maradványnak, sem teljesen kész aktív feature-nek tekinteni üzleti döntés nélkül.

A `docs/PRICING_MODES.md` dokumentumot frissítettük, hogy ezt nyitott, de aktívan számításba vett rétegként rögzítse.

**Döntendő:** megtartjuk és adminból kezelhető fix user-díjként teljesen visszaemeljük, vagy megszüntetjük/migráljuk.

## P0-2 – Funkcionális Specifikáció v1.0 és aktuális baseline eltérései

**Státusz: IGAZOLT, dokumentum-hierarchia döntés szükséges.**

A régi FS több olyan korábbi követelményt tartalmaz, amelyet későbbi explicit döntések módosítottak vagy elhalasztottak, például:
- userenkénti vs globális névláthatóság;
- XLSX vs jelenlegi CSV riport/export scope;
- foglalási e-mail-visszaigazolás;
- befizetések aktív UI-ja;
- heti nézet prioritása.

Az új baseline elején van precedenciaszabály, de egy nulláról induló csapat számára biztonságosabb egyértelműen megjelölni a régi FS státuszát.

**Ajánlás:** az FS v1.0 maradjon történeti/specifikációs forrás, de kapjon explicit `SUPERSEDED / történeti` státuszt; a `CURRENT_FUNCTIONAL_BASELINE.md` legyen az aktuális as-built funkcionális referencia, és az eltéréseket külön changelog dokumentálja.

## P0-3 – UAT dokumentáció lemaradása

**Státusz: IGAZOLT. Dokumentációs feladat + részben új manuális bizonyítás szükséges.**

A korábbi UAT checklist a 2026-08-22–25 között beépített funkciók jelentős részét még nem tartalmazza önálló UAT-esetként.

Kiegészítendő legalább:
- onboarding és számlázási/adószám szabály;
- CSV user import;
- room group `can_book` vs `can_repeat` védelem;
- stabil calendar color + privacy;
- Foglalás címe;
- tiered/progressive/free admin beállítás és érvényesség;
- Tréningterem egyedi csoportos díj;
- foglalás+díj atomi rollback;
- settlement immutabilitás;
- last-admin guard;
- Befizetések URL/UI eltávolítás.

Automatikusan igazolt tételeket a bizonyítékmátrixba kell kötni. A valóban böngészős viselkedést igénylő tételekre külön manuális UAT szükséges; korábbi chatbeli megfigyelés nem helyettesíthet formális futási jegyzőkönyvet production GO előtt.

## P1-1 – Sorozat scope pontos szemantikája

**Státusz: ELFOGADVA dokumentációs hiányként.**

A `Skedda-szerű` megfogalmazás önmagában nem elég egy technológiafüggetlen újraimplementáláshoz. A jelenlegi kód tényleges scope szemantikáját külön dokumentálni kell booking/series/occurrence és Tréningterem díj viselkedéssel.

## P1-2 – Foglalási e-mail-visszaigazolás

**Státusz: IGAZOLT üzleti scope-eltérés; döntés szükséges.**

Korábbi FS/architektúra dokumentum említi, a jelenlegi elfogadott baseline nem tekinti kész feature-nek. Explicit döntés kell: kötelező go-live feature vagy későbbi fázis.

## P1-3 – Payment backend állapota

**Státusz: ELFOGADVA pontosításként.**

A payment backend 2026-08-25-én aktívan fejlesztett migrációkat tartalmaz, de az admin UI tudatosan ki lett véve az aktuális foglaló scope-ból. Újraimplementálás szempontjából a jelenlegi aktív rendszerhez nem kötelező user-facing payment funkcióként reprodukálni; a meglévő backend történeti/parkoltatott képességként dokumentálandó.

## P1-4 – `PRICING_MODES.md` elavult következő lépés

**Státusz: JAVÍTVA.**

A dokumentum frissítve: a havi díjszámító motor elkészültként szerepel, és a fix override nyitott státusza is rögzítve.

## P2 – Admin riport Foglalás címe

**Státusz: JAVÍTVA.**

A `docs/ADMIN_REPORTING_RULES.md` tételes aktív foglalás mezői és CSV-követelménye most már explicit tartalmazza a `Foglalás címe` mezőt.

## További P2 feladatok

Nyitott, de döntést nem feltétlenül igénylő dokumentációs feladatok:
- Duplikálás külön UAT-eset;
- payment logikai entitások inaktív/parkoltatott jelöléssel;
- admin proxy-foglalásnál pricing/advance-limit szemantika explicit leírása;
- ismert mobil scroll probléma/nyitott UX pont baseline-ba történő konzisztens átvezetése.

## Production dokumentációs kapu

A `CURRENT_FUNCTIONAL_BASELINE.md` csak akkor emelhető 100%-os újraimplementálási referenciává, ha:
1. a fix user óradíj üzleti státusza eldőlt;
2. a régi FS dokumentumhierarchia eldőlt;
3. az e-mail-visszaigazolás go-live státusza eldőlt;
4. a payment backend jövőbeni scope-ja egyértelműen meg van jelölve;
5. a friss funkciók UAT checklistje és futási jegyzőkönyve elkészült;
6. a sorozat scope szemantika önállóan, kódhivatkozás nélkül reprodukálható módon dokumentált.
