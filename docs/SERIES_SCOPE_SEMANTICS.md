# A-Hely foglalási rendszer – Ismétlődő sorozatok szerkesztési és lemondási szemantikája

Dátum: 2026-08-26
Állapot: **kanonikus részletspecifikáció a CURRENT_FUNCTIONAL_BASELINE §11-hez**

## 1. Cél

Ez a dokumentum pontosan rögzíti az ismétlődő foglalások három user-facing műveleti hatókörének jelentését. A cél, hogy az `Aktuális alkalom`, `Ettől kezdve` és `Teljes sorozat` kifejezések ne UI-metaforák legyenek, hanem technológiától független, tesztelhető üzleti szabályok.

A jelenlegi PostgreSQL implementáció referenciafüggvényei:
- `update_booking_scope`;
- `cancel_booking_scope`.

A konkrét táblanevek új implementációban eltérhetnek, de az alábbi viselkedés nem.

## 2. Közös definíciók

**Kiválasztott alkalom:** az a konkrét aktív booking, amelyről a user/admin a műveletet indítja.

**Jövőbeli alkalom:** olyan aktív booking, amelynek kezdete a művelet végrehajtásakor még a jövőben van.

**Sorozat:** minden olyan booking, amely ugyanahhoz a logikai `booking_series` entitáshoz tartozik.

A scope-műveletek kizárólag aktív, jövőbeli foglalásokat módosítanak vagy mondanak le. Már lezajlott alkalmat sorozat-scope művelet nem ír át visszamenőleg.

A sorozat eredeti generálási/occurrence struktúrája történeti auditforrás marad. Az élő aktuális állapot forrása a bookingok állapota; a scope-műveletek történetét külön műveleti/auditnapló őrzi.

## 3. Hatókörök

### 3.1 Aktuális alkalom (`occurrence`)

Csak a kiválasztott konkrét jövőbeli aktív booking érintett.

Nem érintett:
- a sorozat korábbi alkalmai;
- a sorozat későbbi alkalmai;
- maga a sorozat ismétlődési definíciója.

### 3.2 Ettől kezdve (`following`)

A kiválasztott booking **és minden nála később kezdődő, ugyanahhoz a sorozathoz tartozó aktív jövőbeli booking** érintett.

Nem érintett:
- a kiválasztott alkalomnál korábban kezdődött booking;
- már lezajlott alkalom;
- cancelled booking.

### 3.3 Teljes sorozat (`series`)

A sorozat **összes, a művelet pillanatában még jövőbeli és aktív bookingja** érintett, függetlenül attól, hogy a műveletet a sorozat melyik jövőbeli alkalmáról indították.

Már lezajlott vagy korábban lemondott alkalom nem változik.

Ezért a `Teljes sorozat` nem történeti visszaírást jelent, hanem a teljes még élő jövőbeli sorozatrészt.

## 4. Szerkesztés (`update`)

### 4.1 Transzformáció

A kiválasztott alkalom új kezdési ideje és régi kezdési ideje közötti különbségből a rendszer egy időeltolást (`delta`) képez.

A kiválasztott új befejezés és új kezdés különbsége adja az új időtartamot.

Minden, a scope által érintett bookingra ugyanaz alkalmazandó:
- új helyiség;
- azonos időeltolás a saját korábbi kezdéséhez képest;
- azonos új időtartam;
- új használattípus;
- új megjegyzés.

Példa: ha a kiválasztott heti alkalom 10:00-ról 11:30-ra kerül és az új időtartam 90 perc, akkor `following` esetén minden érintett későbbi alkalom a saját eredeti kezdéséhez képest +90 perccel tolódik, és 90 perces lesz.

### 4.2 Nem módosított adatok

A scope-szerkesztés nem hoz létre új booking-series entitást, és nem írja át visszamenőleg az eredeti recurrence-generálási auditot.

Az olyan foglalásspecifikus adat, amelyre a szerkesztési kérés nem ad új értéket, megmarad, kivéve ha egy adatbázis-invariáns a helyiség/használattípus változása miatt szükségszerűen módosítja.

A `booking_title` a jelenlegi scope-szerkesztésben nem része a tömegesen módosított mezőknek, ezért a már meglévő bookingcím foglalásonként megmarad.

## 5. Tréningterem csoportos díj szerkesztéskor

A `group_hourly_rate_huf` foglalásspecifikus pénzügyi adat; a scope-szerkesztés önmagában **nem terít szét új egyedi csoportos díjat a sorozatra**.

Kötelező szemantika:
- ha egy már Tréningterem + Csoportos booking Tréningterem + Csoportos marad, a bookingon tárolt saját csoportos óradíj megmarad, így a korábban egyedileg beállított 5000/7500/stb. érték nem vész el;
- ha a módosítás eredményeként a booking már nem Tréningterem + Csoportos, a speciális csoportdíj nem maradhat aktív rajta és nullázódik;
- ha a booking korábban nem Tréningterem + Csoportos volt, de a módosítás azzá teszi, és nincs meglévő booking-specifikus csoportdíja, a default **5000 Ft/óra** alkalmazandó;
- új egyedi csoportdíj tömeges beállítása külön, explicit admin díjműveletet igényel; nem következhet implicit módon egy scope-szerkesztésből.

Normál user ismétlődő Tréningterem-sorozatot nem kezelhet sorozatként; ezt backend/DB szinten is védeni kell.

## 6. Szerkesztés atomi működése

A rendszer előbb az összes érintett célállapotot validálja.

Minden érintett bookingra újra ellenőrizendő legalább:
- user/room jogosultság;
- foglalási időszabályok;
- előrefoglalási szabály;
- használattípus;
- ütközés.

Ha **bármelyik** érintett alkalom szabálytalan lenne vagy ütközne, a teljes scope-művelet sikertelen; részleges sorozatmódosítás nem maradhat vissza.

A helyiségekre vonatkozó konkurens hozzáférést determinisztikus lockolással/azzal ekvivalens DB-mechanizmussal kell kezelni, és az adatbázis-szintű dupla foglalás elleni védelem továbbra is kötelező.

## 7. Optimista konkurenciavédelem

A művelet indításakor a kiválasztott booking kliens által ismert verzióját/`updated_at` értékét ellenőrizni kell.

Ha a kiválasztott bookingot időközben más módosította, a scope-szerkesztés nem indulhat el elavult állapotból; a usernek frissítenie kell az adatot.

Ez nem helyettesíti a DB-szintű foglalási ütközésvédelmet.

## 8. Lemondás (`cancel`)

A három scope ugyanazt a célhalmazt jelenti, mint szerkesztéskor:
- `occurrence`: csak a kiválasztott jövőbeli aktív booking;
- `following`: kiválasztott + minden későbbi aktív jövőbeli booking ugyanabban a sorozatban;
- `series`: minden aktív jövőbeli booking ugyanabban a sorozatban.

Lemondáskor az érintett booking:
- `cancelled` állapotba kerül;
- többé nem foglalja az idősávot;
- nem számít bele elszámolásba;
- fizikai rekordja nem törlődik;
- cancellation snapshot készül;
- auditrekord készül.

## 9. 24 órás lemondási szabály sorozat-scope esetén

Normál user esetén a teljes célhalmazt **a módosítás előtt** ellenőrizni kell.

Ha a scope által érintett akár egyetlen booking a lemondási cutoffon belül van, a teljes scope-lemondás meghiúsul. Nem lehet olyan részleges eredmény, hogy a távolabbi alkalmak lemondódnak, a cutoffon belüli pedig megmarad.

Adminra a normál user cutoff-tiltása nem vonatkozik.

## 10. Idempotencia és audit

A scope-művelet idempotenciakulcshoz kötött.

Azonos actor + azonos idempotenciakulcs + azonos request ismétlése nem hozhat létre második műveletet; ugyanazon kulcs eltérő payloadra nem használható.

A rendszernek visszakövethetően tárolnia kell legalább:
- actor;
- action (`update` / `cancel`);
- scope;
- kiválasztott booking;
- series azonosító;
- request payload;
- érintett bookingok száma / result;
- bookingonkénti audit előtte/utána vagy cancellation snapshot.

## 11. Sorozat-entitás és occurrence-audit

A scope-szerkesztés/lemon­dás nem jelent új recurrence-generálást.

A `booking_series` eredeti definíciója és a generálás occurrence-auditja nem használható az aktuális bookingállapot helyett a későbbi megjelenítéshez vagy elszámoláshoz. Az aktuális állapot a foglalási rekordokból olvasandó; az eredeti series/occurrence adatok történeti/audit célt szolgálnak.

## 12. Kötelező regressziós tesztek

Legalább:
- occurrence update csak egy bookingot módosít;
- following update a kiválasztottat és minden későbbit módosít, korábbit nem;
- series update minden aktív jövőbeli bookingot módosít, múltat/cancelledet nem;
- időeltolás és új duration minden célbookingra konzisztens;
- egyetlen ütköző célbooking esetén teljes rollback;
- stale `expected_updated_at` esetén nincs módosítás;
- occurrence/following/series cancel célhalmaz helyes;
- cutoffon belüli egyetlen target normál usernél teljes rollbacket okoz;
- admin cutoff bypass;
- idempotens ismétlés nem duplikálja a hatást/auditot;
- booking_title megmarad scope update után;
- Tréningterem + Csoportos → Tréningterem + Csoportos esetén booking-specifikus csoportdíj megmarad;
- Tréningterem/Csoportos státusz elhagyásakor speciális díj nullázódik;
- új Tréningterem + Csoportos státusz esetén default 5000 Ft/óra kerül alkalmazásra;
- normál user sorozatként nem kezelhet ismétlődő Tréningterem-foglalást.

## 13. Újraimplementálási invariáns

Más adatmodellel/frameworkkel épített utód csak akkor ekvivalens, ha a fenti scope-célhalmaz, atomi működés, pénzügyi adatmegőrzés, jogosultság, idempotencia és audit szemantika változatlanul teljesül.
