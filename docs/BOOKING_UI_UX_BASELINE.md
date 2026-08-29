# A-Hely foglalási UI/UX baseline – regresszióvédelmi dokumentum

Dátum: 2026-08-20

Állapot: **kötelezően megőrzendő baseline**

Ez a dokumentum a stagingen elfogadott foglalási felület és mobil működés tartós referenciaforrása. Új UI/UX fejlesztés, refaktor vagy reszponzív módosítás **nem távolíthat el és nem ronthat vissza** itt felsorolt működést külön üzleti döntés nélkül.

A cél az, hogy az A-Hely felhasználói a jelenlegi Skedda/AllBooked használati mintához minél közelebbi, kevés újratanulást igénylő rendszert kapjanak. Nem pixelpontos másolat a cél, hanem a megszokott használati logika és képernyőkihasználás megőrzése.

## 1. Napi foglalási naptár – általános

- Alapértelmezett foglalási felület a napi, többhelyiséges naptár.
- Nyitvatartási sáv: **07:00–22:00**.
- Desktopon a teljes 07:00–22:00 sáv lehetőség szerint egy képernyőn belül áttekinthető, Skedda-szerű tömör függőleges skálával.
- A helyiségek oszlopokban jelennek meg.
- A user csak a számára látható/foglalható helyiségeket látja a jogosultsági szabályok szerint.
- Saját foglalás vizuálisan elkülönül.
- Más felhasználó foglalásának neve a névláthatósági szabály szerint jelenik meg.
- A foglalás blokkok időarányosan jelennek meg a rácson.
- Az egész órás vízszintes rácsvonal hangsúlyosabb, a félórás vonal finomabb.
- Az óracímkék az adott órasáv belsejében, függőlegesen és vízszintesen középre igazítva jelennek meg.
- Az egész órás vonal megszakítás nélkül végigfut a bal oldali időoszlopon és pontosan folytatódik a helyiségoszlopokban.
- Az időoszlop vonalai, a helyiségoldali rács és a foglalási blokkok ugyanabból a percalapú naptárgeometriából számítandók; külön CSS-eltolással vagy címkéhez kötött pszeudo-vonallal nem helyettesíthetők.
- Ez a 2026-08-21-én UAT-elfogadott megjelenés kötelező baseline mobil portrait, iPad/tablet landscape és laptop/desktop nézetben is.

## 2. Mobil napi naptár – kötelező viselkedés

- A felső sávban **7 egymást követő nap** látszik: a kiválasztott nap és a következő 6 nap.
- A kiválasztott nap kör alakú vizuális kiemelést kap.
- Külön naptár ikon nyit havi dátumválasztót; innen tetszőleges napra lehet ugrani.
- A régi, nagy `Előző / Ma / Következő / Mutasd / Ismétlődő` mobil blokk nem térhet vissza.
- A bal oldali órasáv **vízszintes görgetésnél sticky/fix** marad (`position: sticky; left: 0` jellegű működés).
- A 07:00 címke teljesen látható.
- A naptár teljes felületén lehessen természetesen függőlegesen görgetni; ne csak az órasávon.
- A fel-le görgetés nem indíthat azonnal foglalást.
- Mobilon foglaláskijelölés csak **long press** után indul.
- Long press előtt megkezdett scroll megszakítja a kijelölési szándékot.
- A long press során az iOS/Safari natív szövegkijelölése és touch callout nem jelenhet meg a naptáron.
- A kijelölt idősáv ujjfelengedésekor **azonnal megnyílik a foglalási ablak**; mobilon nincs köztes „Foglalás” gomb.
- A foglalási modál megnyitásakor nem maradhat kék Safari szövegkijelölés.

## 3. Foglalás indítása

Két támogatott beviteli mód van, mindkettőt meg kell őrizni:

1. **naptárból történő kijelölés**;
2. jobb alsó, fix **`+` gyorsfoglalás** gomb.

A jobb alsó `+` gomb mobilon és desktopon is elérhető marad. Refaktor során nem kerülhet olyan fejlécbe vagy konténerbe, amely mobilon elrejti.

A naptárból kijelölt foglalásnál a kijelölt helyiség, dátum, kezdés és befejezés előre töltődik a modálba, de ott még módosítható.

## 4. Foglalási ablak

- A foglalás modálban módosítható a helyiség, dátum, kezdés, befejezés és megjegyzés.
- Normál helyiségnél a használat automatikusan **Egyéni**; külön Egyéni/Csoportos választó nem jelenik meg.
- Az **Egyéni/Csoportos** választó csak a **Tréningterem** esetén jelenik meg.
- A Tréningterem neve a helyiségfejlécben csak **egyszer** jelenhet meg; duplikált alcím/címke nem lehet.
- Egyszeri és ismétlődő foglalás **ugyanabból a foglalási ablakból** indul, Skedda-szerűen.
- Az ismétlődés külön főoldali mobil gombként nem jelenik meg.
- Ismétlődés gyakorisága: napi, heti, kétheti, havi.
- Ismétlődési lehetőség csak akkor aktív, ha a backend jogosultság (`list_repeatable_rooms`) ezt engedi.
- Az ismétlődő foglalás továbbra is a meglévő backend sorozat-létrehozási folyamatot használja; UI nem kerülheti meg a szerveroldali szabályokat.
- A sorozat vége ugyanebben a foglalási ablakban két módon adható meg: **alkalmak száma alapján** vagy **végdátum alapján**. A választott módhoz tartozó mező kötelező, a másik nem kerül elküldésre.
- Kivételdátumok kiválasztása későbbi finomításnál naptáras, Skedda-szerű megoldás legyen; szöveges lista nem tekintendő végleges UX-nek.
- Mentés nélküli bezáráskor az ideiglenes `Új foglalás` kijelölés kötelezően eltűnik; X, Mégse és backdrop bezárás sem hagyhat fantom blokkot a naptárban.

## 5. Mobil felső navigáció

- Mobilon kompakt **A-Hely + hamburger** navigáció használatos.
- A menü tartalmazza legalább: Foglalási naptár, Foglalásaim, kijelentkezés; adminnál az admin menüpontokat is.
- Bármely menüpont kiválasztásakor a lenyíló menü **azonnal bezár**.
- Route-váltás után a menü nem maradhat nyitva.
- A desktop navigáció ettől függetlenül megmarad.

## 6. Saját foglalások

- A saját foglalások külön oldalon elérhetők.
- Jóváhagyott további UX-cél: saját foglalásoknál a naptárnézet legyen alapértelmezett, napi és havi nézettel, dátumra ugrással; a meglévő lista nézet megmaradhat.
- Ez a saját-foglalás naptár továbbfejlesztés még nem tekintendő minden elemében késznek, ezért implementálásakor a jelenlegi lista funkcióit nem szabad elveszíteni.

## 7. Foglalási üzleti szabályok, amelyeket UI-refaktor sem írhat felül

- időegység: 30 perc;
- minimum foglalás: 60 perc;
- csak jövőbeli időpontra lehet foglalni;
- ütközést backend/adatbázis oldalon is ellenőrizni kell;
- jogosulatlan helyiségre manipulált klienssel sem lehet foglalni;
- előrefoglalási limit backend oldali szabály;
- default normál előrefoglalási limit adminból állítható (projektkontextus szerinti aktuális érték/szabály az irányadó);
- Tréningterem külön előrefoglalási szabálya adminból állítható;
- normál user 24 órán belüli lemondása tiltott; távolabbi saját foglalás lemondható;
- ismétlődő foglalás ütközéskezelése a jóváhagyott két módot támogatja: teljes sorozat megszakítása vagy szabad alkalmak létrehozása.

## 8. UAT során manuálisan igazolt működések

A 2026-08-20-i és 2026-08-21-i manuális UAT során sikeresen igazoltuk többek között:

- normál foglalás létrehozása;
- minimum 60 perces foglalási szabály;
- múltbeli foglalás tiltása;
- átfedő foglalás elutasítása;
- ismétlődő sorozat létrehozása;
- ismétlődő kivételdátum kezelése;
- ismétlődő ütközésnél mindkét üzleti opció működése;
- USER-B foglalása USER-A számára látható a jogosultsági/névláthatósági szabály szerint;
- eltérő helyiségjogok megjelenése;
- inaktív user hozzáférésének tiltása;
- 24 órán belüli lemondás tiltása;
- 24 órán túli saját foglalás lemondása;
- előrefoglalási limit érvényesülése;
- mobil long-press + scroll viselkedés fejlesztési baseline-ja;
- mobil menü automatikus bezárása navigációkor;
- mentetlen naptári kijelölés megszakításkor eltűnik;
- más felhasználó foglalóneve a névláthatósági beállítás szerint megjelenik;
- naptárból Szerkesztés / Duplikálás / Törlés műveletek elérhetők;
- ismétlődő foglalás szerkesztésénél és törlésénél a három Skedda-szerű hatókör megmarad.

A részletes UAT státuszok forrása továbbra is `docs/FUNKCIONALIS_UAT_CHECKLIST.md` és `docs/UAT_FUTASI_JEGYZOKONYV.md`.

## 9. Ismert / nyitott UX feladatok

Ezeket nem szabad összekeverni a már elfogadott baseline elemekkel:

- mobil függőleges görgetés 18:00 körüli időszakos „megakadása” kivizsgálandó; a kívánt állapot az egyetlen folyamatos scroll 07:00–22:00 között;
- saját foglalások naptárnézetének teljes megvalósítása;
- ismétlődő foglalás kivételdátumainak Skedda-szerű naptárválasztója;
- további pixel/spacing finomítások a Skedda képernyőkihasználásához.

## 10. Regresszióvédelmi szabály

Minden, a foglalási naptárt, mobil CSS-t, foglalási modált vagy navigációt érintő PR előtt és után ellenőrizni kell legalább:

- bal órasáv sticky maradt-e;
- mobil scroll működik-e a teljes naptáron;
- long press nem vált-e vissza azonnali kijelölésre;
- ujjfelengedés után megnyílik-e a foglalási modál;
- a `+` gyorsfoglalás megmaradt-e;
- 7 napos felső sáv és naptár ikon megmaradt-e;
- ismétlődés a foglalási ablakban maradt-e;
- ismétlődő foglalásnál az alkalomszámos és a végdátumos lezárás is választható-e;
- normál szobánál nincs-e Csoportos választó;
- Tréningterem neve nincs-e duplázva;
- mobil hamburger menü navigáció után bezár-e;
- egész órás vízszintes rácsvonalak és óracímkék igazítása nem romlott-e;
- mentés nélküli modalbezárás eltávolítja-e az ideiglenes kijelölést;
- foglaló névláthatósága a profil/admin beállítást követi-e;
- naptári Szerkesztés / Duplikálás / Törlés megmaradt-e;
- sorozat szerkesztés/törlés mindhárom hatókört felajánlja-e;
- a backend foglalási/jogosultsági szabályok változatlanul érvényesülnek-e.

Ha egy új fejlesztés ezen pontok bármelyikét szándékosan megváltoztatná, az **új üzleti/UI döntésnek** minősül, és előbb ezt a dokumentumot és a projektkontextust kell frissíteni.

## 11. Verziózott állapotmentés

A 2026-08-21-én UAT-olt aktuális működés részletes, regresszióvédett pillanatképe:

`docs/STATUS_SNAPSHOT_2026-08-21_CALENDAR_UX_AND_BOOKING_ACTIONS.md`

Új naptár-, mobil-, booking-action- vagy foglalási modal fejlesztés előtt ezt a snapshotot kötelező elolvasni. Ha eltérés van egy régebbi beszélgetési állapot és e dokumentum között, a repositoryban rögzített aktuális baseline/snapshot az irányadó, kivéve új, kifejezett üzleti döntés esetén.
