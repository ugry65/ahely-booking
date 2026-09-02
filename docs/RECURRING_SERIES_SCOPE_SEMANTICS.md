# A-Hely – Ismétlődő foglalások scope szemantikája

Dátum: 2026-08-26
Státusz: kanonikus kiegészítő specifikáció a `CURRENT_FUNCTIONAL_BASELINE.md` §11-hez.

## Cél

Ez a dokumentum technológiától függetlenül rögzíti az ismétlődő foglalások szerkesztési és lemondási hatóköreit. Egy új implementációban a konkrét táblák/RPC-k eltérhetnek, de az alábbi user-facing és történeti szemantikának változatlanul meg kell maradnia.

## Három scope

A sorozat egy konkrét, aktív jövőbeli alkalma (`selected occurrence`) a kiindulópont.

### 1. Aktuális alkalom (`occurrence`)

Csak a kiválasztott konkrét foglalás érintett.

- szerkesztéskor csak ennek a bookingnak a helyisége, kezdete, vége, használattípusa, megjegyzése/címe módosul a támogatott mezők szerint;
- lemondáskor csak ez az alkalom válik `cancelled` állapotúvá;
- a sorozat korábbi és későbbi alkalmai változatlanok;
- a sorozat-definíció és az eredeti generálási audit-pillanatkép nem íródik vissza történetileg.

### 2. Ettől kezdve (`following`)

A kiválasztott alkalom **és ugyanazon sorozat minden későbbi, még aktív és jövőbeli alkalma** érintett.

Szerkesztéskor:
- a kiválasztott alkalomhoz képest számított időeltolás (`delta`) minden érintett bookingra azonosan alkalmazódik;
- az új foglalási időtartam minden érintett bookingra azonos;
- a célhelyiség, használattípus és támogatott tartalmi mezők az érintett alkalmakon egységesen változnak;
- a kiválasztott alkalom előtti bookingok változatlanok.

Lemondáskor:
- a kiválasztott alkalom és az összes későbbi aktív jövőbeli alkalom `cancelled` lesz;
- a korábbi alkalmak története változatlan.

### 3. Teljes sorozat (`series`)

A sorozat **összes még aktív, jövőbeli foglalása** érintett, függetlenül attól, melyik konkrét jövőbeli alkalomról indult a művelet.

- már lezajlott/múltbeli alkalmakat a művelet nem ír vissza;
- már korábban cancelled alkalmak nem aktiválódnak újra és nem módosulnak;
- szerkesztéskor minden érintett aktív jövőbeli booking ugyanazt az eltolást/időtartamot/célkonfigurációt kapja;
- lemondáskor minden aktív jövőbeli booking cancelled lesz.

## Atomi működés

A több alkalmat érintő szerkesztés és lemondás üzleti értelemben atomi.

Szerkesztéskor a rendszer előbb **minden érintett célállapotot validál** (jogosultság, idő, helyiség, előrefoglalási szabály, ütközés). Ha bármely érintett booking érvénytelen vagy ütközne, a teljes scope-művelet hibázik, és egyik érintett booking sem maradhat részlegesen módosítva.

Lemondáskor normál user esetén a lemondási cutoffot minden érintett bookingra ellenőrizni kell. Ha akár egy érintett alkalom már a tiltott időablakban van, a teljes scope-művelet meghiúsul. Adminra az admin lemondási szabály érvényes.

## Jogosultság

- normál user csak saját foglalássorozatát kezelheti;
- admin a jogosultsági modell szerint más user sorozatát is kezelheti;
- normál user ismétlődő Tréningterem-foglalást sorozat-scope-ban nem kezelhet; ezt backend/DB oldalon is ki kell kényszeríteni;
- kliensoldali scope-manipuláció nem kerülheti meg a backend ellenőrzést.

## Optimista konkurencia és idempotencia

A művelet a kiválasztott booking aktuális verziójához (`updated_at` vagy ekvivalens verziótoken) kötött. Elavult szerkesztési kérés nem írhatja felül a frissebb állapotot.

Minden scope-művelet idempotenciakulccsal történik. Azonos actor + idempotenciakulcs + azonos request ismételt elküldése ugyanazt az üzleti eredményt adja, nem duplikálja a műveletet. Ugyanaz a kulcs eltérő requesttel hiba.

## Audit és történeti modell

Minden érintett booking külön auditálódik, és a teljes scope-műveletről összesítő audit/műveleti rekord is készül.

A sorozat eredeti occurrence/generálási táblája **audit-pillanatkép**, nem az élő szerkesztett állapot forrása. Az élő állapotot a booking rekordok képviselik; a későbbi sorozat-scope műveletek történetét az audit és a scope-operation log őrzi.

Ez fontos újraimplementálási invariáns: egy új rendszernek nem kell ugyanilyen táblaszerkezetet használnia, de különbséget kell tennie az eredeti sorozat-generálási történet és a később módosított élő booking-állapot között.

## Tréningterem és booking-specifikus csoportos díj

A Tréningterem csoportos admin díja booking-specifikus történeti pénzügyi adat.

A jelenlegi scope-szerkesztés **nem számolja újra és nem törli automatikusan** a már egy konkrét bookinghoz rögzített egyedi csoportos óradíjat. Az egyedi díj a bookinghoz kötve megmarad.

Következmények:
- ha egy Tréningterem Csoportos sorozat több bookingja ugyanazzal az admin által megadott díjjal jött létre, a scope-időpontmódosítás után is minden érintett booking megtartja a hozzá korábban rögzített díjat;
- ha egy booking olyan állapotba kerül, ahol a speciális Tréningterem-csoportos díj üzletileg nem alkalmazandó, a tárolt booking-specifikus díj történeti adatként megmaradhat, de a havi pricing motor csak a ténylegesen Tréningterem + Csoportos foglalásra alkalmazza;
- `Free` user esetén a pricing precedencia miatt a fizetendő ettől függetlenül 0 Ft;
- új admin egyedi díj csak explicit díjmódosítási művelettel állítható be, nem implicit mellékhatása egy sorozat-scope időpontmódosításnak.

## User-facing elérhetőség

A napi naptár booking-kezelési felülete a sorozathoz tartozó bookingnál a három scope-ot használja: `Aktuális alkalom`, `Ettől kezdve`, `Teljes sorozat`.

A `Foglalásaim` részletes booking-kezelő nézete jelenleg szándékosan szűkebb: sorozatalkalom ott külön nem szerkeszthető, de egyedi alkalomként lemondható. Ez nem írja felül a napi naptárban elérhető teljes scope-kezelést.

## Kötelező regressziós/acceptance tesztek

Legalább:
- occurrence update csak egy bookingot érint;
- following update a kiválasztott + későbbi aktív jövőbeli bookingokat érinti;
- series update minden aktív jövőbeli bookingot érint, múltbelit nem;
- occurrence/following/series cancel ugyanezt a hatókört követi;
- több bookingot érintő update ütközés esetén teljes rollback;
- normál user cutoff sérülése bármely érintett bookingnál teljes cancel rollback;
- más user sorozatának jogosulatlan kezelése tiltott;
- normál user Tréningterem series update tiltott;
- idempotens újraküldés nem duplikál;
- elavult optimistic-concurrency kérés tiltott;
- booking-specifikus Tréningterem csoportos díj scope-időpontmódosítás után megmarad és csak a megfelelő booking/use-type/room esetben kerül pricingba.
