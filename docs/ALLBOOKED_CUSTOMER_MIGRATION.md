# AllBooked/Skedda ügyfélmigráció – operátori runbook

Állapot: kötelező production eljárás; 2026-09-14.

## Cél és hatókör

A régi AllBooked/Skedda rendszerből a valódi ügyfeleket egyenként kell átvenni az A-Hely rendszerbe. Egy futás egy ügyfél profilját, helyiségcsoport-jogait és foglalásait kezeli. A Papp Dalma-import volt a sikeres kontrollminta; az általános folyamat ugyanazokat a biztonsági elveket tartja meg.

Az import nem vesz át:

- legacy árat vagy fizetési státuszt;
- megjegyzést;
- számlázási adatot;
- ismétlődő foglalási jogosultságot.

## Előfeltételek

1. A production adatbázis legutóbbi automatikus mentése sikeres és a heartbeat `Up`.
2. Az admin az AllBookedból csak egyetlen ügyfél booking exportját készíti el CSV formátumban.
3. Az export kötelező oszlopai és helyiségnevei nem lettek kézzel átírva.
4. Az ügyfélhez az A-Helyben nincs már kézzel létrehozott foglalás, közvetlen szobajog, ár-felülírás, elszámolás vagy befejezett onboarding. Ilyen állapotban az automatikus import szándékosan leáll, és kézi kivizsgálás kell.

## Import menete

1. Jelentkezz be aktív adminként.
2. Nyisd meg a `Migráció` menüt.
3. Válaszd ki az egy ügyfélhez tartozó CSV-t, majd futtasd a dry-runt.
4. Csak `PASS` eredménynél folytasd. Ellenőrizd a nevet, e-mailt, telefonszámot, foglalásszámot, összes órát, helyiségenkénti darabszámot és az automatikusan levezetett helyiségcsoportokat.
5. Minden Tréningterem-foglalást sorolj `Egyéni` vagy `Csoportos` típusba az eredeti rendszer adatai alapján. Bizonytalan besorolással tilos importálni.
6. Írd be pontosan a felületen megjelenő ügyfélspecifikus megerősítést: `IMPORT <email> <foglalásszám>`.
7. Indítsd el egyszer az importot, és várd meg az import utáni reconciliation `PASS` eredményét. Várakozás közben a gomb letiltott; ne frissítsd az oldalt.
8. Hasonlítsd össze a reconciliation foglalásszámát, összpercét, dátumtartományát, csoportjogait és Tréningterem-besorolásait a dry-runnal.
9. A `Felhasználók` oldalon ellenőrizd a profilt, majd külön küldd ki az aktiváló/jelszóbeállító linket.
10. Ismétlődő foglalási jogot csak külön üzleti jóváhagyás alapján állíts be.

## Papp Dalma próbaimport kivezetése

A 2026-09-03–17. közötti, 19×60 és 2×90 perces, összesen 21 Forrás tér-foglalás kizárólag migrációs próba volt. A valódi ügyfélmigráció megkezdése előtt az admin a `Migráció` oldalon, friss sikeres backup után egyszer futtatja a `Papp Dalma próbaimport visszavonása` műveletet a pontos `REMOVE-PAPP-DALMA-TEST-DATA` megerősítéssel.

A művelet csak akkor futhat, ha az Auth/profil azonosság, a 21 tétel, a dátumtartomány, az időtartamok, a helyiség és az üzletiadat-mentesség pontosan egyezik a bizonyított próbával. A foglalások `voided` állapotba kerülnek, ezért a naptárban, havi órákban és lemondási riportban sem aktív, sem lemondott üzleti tételként nem jelennek meg. A próba-csoportjog törlődik, a profil inaktív, üres importállapotba kerül. A megváltoztathatatlan ledger és auditbizonyíték megmarad; ez nem ügyféladatként használt foglalás, hanem a végrehajtott próba visszakövethetősége.

Papp Dalma későbbi valódi exportja az általános, verziózott ujjlenyomatú importtal újra betölthető. A valódi import ismét aktiválja és frissíti a meglévő profilt; a régi 21 voidolt tétel nem keveredik az új reconciliation eredményébe.

## Fail-closed működés

Az import teljes tranzakciója visszagördül, ha bármely foglalás ütközik, a payload eltér a dry-runtól, a csoportjogok nem vezethetők le, a céluser nem biztonságosan üres, vagy a reconciliation eltérést talál. Új Auth user létrehozása után bekövetkező adatbázishibánál a rendszer csak kapcsolódó üzleti adat nélküli profilt törölhet kompenzációként.

Az azonos CSV biztonságosan újrafuttatható: a forrás-ujjlenyomat-ledger nem enged duplikált foglalást. Eltérő tartalom azonos ujjlenyomattal blokkoló hiba.

## Kötelező regressziós ellenőrzés

- dry-run nem ír adatot és nem küld e-mailt;
- több ügyfelet tartalmazó fájl elutasított;
- 30 perces rácsot vagy 60 perces minimumot sértő foglalás elutasított;
- nem kanonikus helyiség elutasított;
- Tréningterem-besorolás nélkül az importgomb nem használható;
- nem admin nem importálhat;
- hiányos vagy többlet csoportjog elutasított;
- aktív ütközésnél nem marad részleges profil-, jog-, booking- vagy ledger-adat;
- azonos forrás újrafuttatása nem duplikál;
- booking title megmarad, note/ár/payment nem kerül át;
- desktop és mobil admin menüben a `Migráció` elérhető, mobilon a menü navigáláskor bezár;
- a foglalási naptár desktop és mobil baseline-jához az import fejlesztése nem nyúlhat.

## Production korlát

A production adatbázis-séma migrációját külön, jóváhagyott database-deploy workflow-val kell alkalmazni. A PR, a Vercel preview vagy az adminfelület megnyitása önmagában nem módosíthat production adatbázist. Importot kizárólag aktív admin, a production web `main` deploymentjéről indíthat.
