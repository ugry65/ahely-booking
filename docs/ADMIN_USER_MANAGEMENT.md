# Admin felhasználókezelés – üzleti és technikai szabályok

Állapot: elfogadott üzleti döntés; frissítve 2026-08-22.
Kapcsolódó issue-k: #72, #73, #75.

## Felhasználó létrehozása

Az admin egy új felhasználónál csak a következő adatokat köteles megadni:
- vezetéknév;
- keresztnév;
- e-mail cím.

A felhasználó létrehozásakor a rendszer nem küld automatikusan levelet. Az admin a user sorában külön `Aktiváló / jelszóbeállító link küldése` művelettel indítja az első belépést.

## Kötelező első belépési adatkitöltés

Az első jelszóbeállítás után a normál user addig nem használhatja a foglalási rendszert, amíg a saját adatkitöltését be nem fejezte.

Kötelezően megadandó:
- telefonszám;
- számla típusa: magánszemély vagy vállalkozó;
- számlázási név;
- számlázási irányítószám;
- számlázási település;
- számlázási utca;
- számlázási házszám.

A számlázási névnél a user választhatja a `A számlázási név megegyezik a nevemmel` opciót. Ebben az esetben a rendszer a profilban tárolt `vezetéknév + keresztnév` értéket automatikusan átemeli a számlázási névhez. Ha nem egyezik meg, a számlázási nevet kézzel kell megadni.

Vállalkozói számlázás esetén az adószám kötelező. Magánszemélynél adószámot nem kérünk. A kötelezőséget a backend/adatbázis is kikényszeríti.

A sikeres első adatkitöltés időpontja `onboarding_completed_at` mezőben rögzül, és a művelet auditált. Az onboarding befejezéséig a normál user a védett foglalási felületekre nem léphet be. Adminra ez az első belépési korlátozás nem vonatkozik.

## Meglévő felhasználók importja

Az admin CSV fájlból töltheti be a jelenlegi felhasználókat. Kötelező oszlopok kizárólag:

`last_name, first_name, email`

Az import:
- admin jogosultsághoz kötött;
- validálja a név/e-mail alapadatokat;
- fájlon belüli duplikált e-mailt hibának tekint;
- már létező e-mailt kihagy;
- új e-mail esetén Auth usert hoz létre automatikus aktiváló/reset e-mail nélkül;
- ideiglenes technikai jelszót nem tárol és nem jelenít meg;
- az import után az admin userenként küldi ki az aktiváló/jelszóbeállító linket.

A számlázási adatokat nem kell importálni: ezeket a user saját maga adja meg az első belépéskor.

## Aktiváló és jelszó-visszaállító link adminból

Az admin aktív userenként külön linkküldő műveletet kap.

- onboarding előtt a gomb jelentése: `Aktiváló / jelszóbeállító link küldése`;
- onboarding után: `Jelszó-visszaállító link küldése`.

Szabályok:
- csak aktív admin indíthatja;
- csak aktív usernek küldhető;
- a cím a profil hitelesített e-mail címe;
- jelszó, reset token és reset URL nem kerül audit payloadba vagy alkalmazásadatbázisba;
- az admin művelet auditálva van;
- a tényleges jelszóbeállítás a Supabase recovery folyamaton történik;
- első jelszóbeállítás után a user automatikusan a kötelező adatkitöltésre kerül.

## Admin által megadott kezdőjelszó

Az admin új felhasználó létrehozásakor legalább 12 karakteres kezdőjelszót ad meg és megerősít. A jelszó csak az Auth-szolgáltatásnak kerül átadásra; a `profiles` táblában nem tároljuk, auditba és alkalmazásnaplóba nem kerül.

Az új felhasználó `must_change_password` jelzővel jön létre. Sikeres belépés után a rendszer kizárólag a jelszócsere oldalt engedi elérni, és a foglalási vagy adminfelület közvetlen URL-ről sem használható. A saját új jelszó sikeres mentése auditáltan kikapcsolja ezt a jelzőt; ezután a normál usernél továbbra is kötelező az első adatkitöltés.

Az Auth-felhasználó létrehozásának hibája nem jelenik meg nyers technikai tartalommal. A rendszer a duplikált e-mailt elkülöníti, egyéb hibát biztonságosan naplóz és érthető adminüzenetet ad.

## Felhasználói lista és szerepkör

A `Felhasználók` adminoldal elsődleges nézete áttekinthető lista. Legalább a következők látszanak:
- név;
- e-mail;
- telefonszám;
- hozzárendelt aktív helyiségcsoportok;
- szerepkör;
- aktív/inaktív állapot.

Név, e-mail és telefonszám alapján kereshető. A kiválasztott user külön szerkesztő nézetben módosítható.

A szerepkör `Normál felhasználó` vagy `Adminisztrátor`. A szerepkör-változás auditált backend művelet. Az utolsó aktív adminisztrátort sem lefokozni, sem deaktiválni nem lehet; ezt adatbázis/backend oldali védelem kényszeríti ki, nem csak a felület.

## Helyiségcsoportok – 2026-08-22-i felülvizsgált döntés

Ez a rész **felülírja** a korábbi döntést, amely szerint nem használunk hozzáférési csoportokat.

A helyiségcsoport célja az adminisztrációs hibák csökkentése: egy userhez nem kell minden szobát külön bejelölni, ha egy üzleti helyszín teljes szobakészletét használhatja.

Kanonikus induló csoportok:
- `A-Hely`: Gyerek szoba, Pitypang szoba, Csoport szoba;
- `Másik Hely`: 1.Szoba-családi, 2.Szoba, 3.Szoba, 4.Szoba, 5.Szoba, 6.Szoba;
- `Tréningterem`: Tréningterem;
- `Forrás tér`: Forrás tér.

Egy user több helyiségcsoport tagja is lehet.

Az effektív jogosultság:

`közvetlen user–szoba jog + aktív helyiségcsoportokból kapott foglalási jog`

Fontos korlátozás: **helyiségcsoport csak foglalási (`can_book`) jogot adhat. Ismétlődő foglalási (`can_repeat`) jog kizárólag közvetlen user–szoba jogosultság lehet.** Ezt a backend is kikényszeríti.

A meglévő közvetlen jogosultságokat csoport bevezetésekor nem szabad törölni vagy felülírni. Ezek egyedi kivételként továbbra is érvényesek.

A helyiségek és helyiségcsoportok külön `Helyiségek` admin menüben kezelendők. A közvetlen user–szoba kivételek és repeat jogok mindaddig külön kompatibilitási felületen is megmaradnak, amíg az új user-admin folyamat teljesen át nem veszi őket.

## Stabil user-szín a foglalási naptárban

Minden profil tartós `calendar_color` értéket kap. A szín nem oldalbetöltésenként random, hanem ugyanahhoz a userhez stabilan kapcsolódik.

A rendszer 40 színes palettát használ. Az első 40 user lehetőség szerint külön színt kap; később a legkevésbé használt palettaszín ismétlődhet.

Adatvédelmi szabály:
- admin minden user színét láthatja;
- normál user a saját foglalásának színét mindig látja;
- ha a globális `Más foglalók neve látható` beállítás be van kapcsolva, más userek színe is megjelenhet;
- ha a névláthatóság ki van kapcsolva, más user neve **és stabil színe sem kerülhet ki a backendből**, mert a szín önmagában is azonosításra használható. Ilyenkor mások foglalása semleges `Foglalt` megjelenést kap.

## Naptári névláthatóság

A más foglalók nevének láthatósága globális beállítás, nem userenkénti kapcsoló. Alapállapotban a nevek láthatók; kikapcsolva más user foglalásánál csak a foglaltság látható, a saját foglalás felismerhető, admin számára az adminisztrációs név látható marad. A stabil user-szín ugyanezt az adatvédelmi szabályt követi.

## Admin foglalás más user nevében

Admin foglalási ablakban aktív felhasználó választható. A foglalás tulajdonosa a kiválasztott user, az audit `actor_user_id` értéke a végrehajtó admin.

Normál user sem kliens-, sem backend-oldalon nem adhat meg tetszőleges másik `user_id`-t.
