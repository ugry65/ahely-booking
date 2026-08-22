# Admin felhasználókezelés – üzleti és technikai szabályok

Állapot: elfogadott üzleti döntés, 2026-08-21.
Kapcsolódó issue-k: #72, #73.

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

## Admin felület egyszerűsítése

A hozzáférési csoportok nem részei a cél üzleti modellnek. A helyiségjogok explicit, userenkénti jogosultságok.

A Tréningterem külön admin-checkboxa megszűnik. Egyetlen Tréningterem van, a speciális üzleti szabályokat stabil rendszerazonosítás kezeli.

A más foglalók nevének láthatósága globális beállítás, nem userenkénti kapcsoló. Alapállapotban a nevek láthatók; kikapcsolva más user foglalásánál csak a foglaltság látható, a saját foglalás felismerhető, admin számára az adminisztrációs név látható marad.

## Admin foglalás más user nevében

Admin foglalási ablakban aktív felhasználó választható. A foglalás tulajdonosa a kiválasztott user, az audit `actor_user_id` értéke a végrehajtó admin.

Normál user sem kliens-, sem backend-oldalon nem adhat meg tetszőleges másik `user_id`-t.
