# UAT bizonyítékaudit – 2026-08-31

## Cél

A `docs/UAT_DELTA_2026-08-31_PR94.md` után fennmaradó 20 `EGYEZTETENDŐ` tétel szakmai felülvizsgálata. A cél nem a már elfogadott modulok újrafuttatása, hanem annak eldöntése, hogy a meglévő kézi, UI-baseline és automatikus bizonyíték közvetlenül igazolja-e az adott checklist elvárt eredményét.

## Döntési elv

Egy tétel lezárható automatikus vagy kombinált bizonyítékkal, ha a checklist elvárt eredménye nem kifejezetten vizuális/interakciós minőség, és a meglévő regressziós teszt közvetlenül ugyanazt az üzleti invariánst bizonyítja. Hiányzó régi kattintási napló önmagában nem indok új manuális UAT-ra.

## Meglévő bizonyítékkal lezárható tételek

### BOOK

- **UAT-BOOK-04 – SIKERES (kombinált bizonyíték).** A jóváhagyott naptári UI-baseline 30 perces rácsot rögzít; `003_create_booking_rpc.sql` explicit elutasítja a 15 percre eső kezdést/befejezést magyar üzleti hibával. Ez közvetlenül lefedi az UI + backend kikényszerítést.
- **UAT-BOOK-05 – SIKERES (kombinált bizonyíték).** A jóváhagyott naptári baseline 07:00–22:00 működési ablakot rögzít; a közös booking time validation DB-szinten kényszeríti a nyitvatartási határt. Nincs azóta olyan release-releváns UI-változás, amely ezt a baseline-t felülírta volna.

### CANCEL

- **UAT-CANCEL-03 – SIKERES automatikus bizonyítékkal.** `099_calendar_booking_management.sql`: occurrence scope cancel sikeres, pontosan egy occurrence lesz cancelled.
- **UAT-CANCEL-04 – SIKERES automatikus bizonyítékkal.** `004_cancel_booking_rpc.sql`: admin a 24 órás cutoffon belül is lemondhat; booking cancelled marad, settlement kizárás és audit/outbox konzisztens.
- **UAT-CANCEL-05 – SIKERES automatikus bizonyítékkal.** `100_series_scope_semantics.sql`: following cancel a kiválasztott és minden későbbi aktív bookingot lemondja, a korábbiakat érintetlenül hagyja.
- **UAT-CANCEL-06 – SIKERES automatikus bizonyítékkal.** `099_calendar_booking_management.sql`: teljes series cancel után nincs aktív jövőbeli occurrence.
- **UAT-CANCEL-07 – SIKERES automatikus bizonyítékkal.** `100_series_scope_semantics.sql`: cutoffba ütköző teljes scope-cancel elutasított, és egyik booking sem módosul.

### EDIT

- **UAT-EDIT-02 – SIKERES automatikus bizonyítékkal.** `005_update_booking_rpc.sql` a módosítási ütközést elutasítja, az eredeti booking integritását megőrzi.
- **UAT-EDIT-03 – SIKERES automatikus bizonyítékkal.** `005_update_booking_rpc.sql` módosításkor újraellenőrzi a helyiségjogot és jogosulatlan target room esetén elutasít.

### REC

- **UAT-REC-02 – SIKERES automatikus bizonyítékkal.** `009_recurring_booking_rpc.sql`: kétheti sorozat létrejön, az occurrence-ok közti különbség explicit 14 nap.
- **UAT-REC-04 – SIKERES automatikus bizonyítékkal.** `009_recurring_booking_rpc.sql`: havi ismétlődés január 31-ről rövid februárban hónapvégre igazodik, majd visszatér az eredeti naptári napra; szökőév is külön assertion.
- **UAT-REC-09 – SIKERES automatikus bizonyítékkal.** A korábbi teljes DB regressziós csomagban az `009_recurring_booking_rpc.sql` őszi és tavaszi DST-falióra eseteket explicit ellenőriz; ez időzóna-szemantika, nem vizuális UAT-követelmény.
- **UAT-REC-10 – SIKERES automatikus bizonyítékkal.** `100_series_scope_semantics.sql`: occurrence update pontosan egy bookingot módosít.
- **UAT-REC-11 – SIKERES automatikus bizonyítékkal.** `099_calendar_booking_management.sql`: following update a kiválasztott és későbbi occurrence-okat együtt módosítja, az elsőt változatlanul hagyja.
- **UAT-REC-12 – SIKERES automatikus bizonyítékkal.** `100_series_scope_semantics.sql`: series update minden aktív jövőbeli targetre alkalmazza az új mezőket.
- **UAT-REC-14 – SIKERES automatikus bizonyítékkal.** `100_series_scope_semantics.sql`: scope update a `booking_title` mezőt megőrzi, valamint a Tréningterem speciális rate állapotának konzisztens átmenetét külön ellenőrzi.

### UX

- **UAT-UX-04 – SIKERES automatikus bizonyítékkal.** A checklist elvárt eredménye: dupla kattintás / lassú kérés esetén ne jöjjön létre duplikált üzleti rekord. Ezt közvetlenül védi és bizonyítja az idempotens `create_booking` regresszió, valamint a párhuzamos booking creation teszt és az adatbázis-szintű overlap védelem. A követelmény nem vizuális animáció vagy gombállapot, hanem üzleti duplikációmentesség.

## Két célzott automatikus pótlás

A bizonyítékaudit két olyan esetet talált, ahol az üzleti működés valószínűleg helyes és részleges/történeti bizonyíték volt, de egy rövid determinisztikus regresszió indokolt:

- **UAT-BOOK-02 – 90 perces foglalás**
- **UAT-BOOK-09 – egymáshoz pontosan érő foglalások**

Ezekhez a PR #97 új `103_booking_duration_and_touching_boundaries.sql` pgTAP tesztje készült. A teszt 10:00–11:30 közötti pontos 90 perces bookingot, majd ugyanabban a helyiségben 11:30–12:30 közötti, pontosan érintkező második bookingot hoz létre és ellenőrzi a mentett határt/időtartamot. A végleges `SIKERES` státusz feltétele a PR #97 teljes Database CI-jének zöld eredménye.

## Egyetlen valódi manuális maradék

- **UAT-UX-05 – CÉLZOTT MANUÁLIS UAT SZÜKSÉGES.** A checklist kifejezetten mobil interakciós minőséget kér: 07:00–22:00 között folyamatos függőleges scroll, és egy régi történeti megjegyzés 18:00 körüli megakadásról nincs véglegesen lezárva. Ezt backend vagy statikus kódreview nem tudja hitelesen bizonyítani. Nem tekintjük hibának, de egyetlen aktuális staging mobil ellenőrzés szükséges.

Minimális ellenőrzés:
1. valódi mobil böngészőben vagy hiteles mobil viewporton nyisd meg a napi naptárat;
2. indulj 07:00 környékéről és folyamatosan görgess 22:00-ig;
3. külön figyeld a 17:30–19:00 szakaszt;
4. PASS, ha nincs megakadás, visszaugrás vagy olyan scroll-lock, amely megakadályozza a nap aljának elérését.

## Várható státusz a PR #97 zöld CI-je után

| Státusz | Darab |
| --- | ---: |
| SIKERES | 71 |
| MODUL-ELFOGADÁS | 22 |
| DÖNTÉSSEL LEZÁRT | 1 |
| EGYEZTETENDŐ / manuális | 1 |
| BLOKKOLT production drill | 3 |
| **Összesen** | **98** |

A 71 SIKERES szám a korábbi 52-höz 19 lezárást ad hozzá. Ez nem 19 új manuális futás: 17 meglévő bizonyíték szakmai lezárása + 2 új célzott automatikus regresszió.

## Production kapu

A funkcionális UAT végleges lezárásához a PR #97 zöld CI-je után csak UAT-UX-05 célzott manuális ellenőrzése marad. Ettől külön, production előtt továbbra is kötelező a három infrastruktúra-drill: backup, tényleges restore, valamint monitoring/alert/recovery.
