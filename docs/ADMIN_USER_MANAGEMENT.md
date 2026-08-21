# Admin felhasználókezelés – üzleti és technikai szabályok

Állapot: elfogadott üzleti döntés, 2026-08-21.
Kapcsolódó issue-k: #72, #73.

## Felhasználói törzsadatok

A profil alapadatai: vezetéknév, keresztnév, e-mail, opcionális telefonszám, aktív státusz.

Opcionális számlázási adatok:
- irányítószám;
- település;
- utca;
- házszám;
- ügyféltípus: magánszemély vagy vállalkozó;
- adószám.

Vállalkozó ügyféltípus esetén az adószám kötelező. Ezt nem csak a UI, hanem a backend/adatbázis is kikényszeríti. Magánszemélynél az adószám opcionális.

## Meglévő felhasználók importja

Az admin CSV fájlból tölthet be meglévő felhasználókat. Kötelező oszlopok: `last_name`, `first_name`, `email`.

Támogatott opcionális oszlopok: `phone`, `customer_type`, `billing_postal_code`, `billing_city`, `billing_street`, `billing_house_number`, `tax_number`, `is_active`.

Az import:
- admin jogosultsághoz kötött;
- validálja a teljes fájl alapadatait a feldolgozás előtt;
- fájlon belüli duplikált e-mailt hibának tekint;
- meglévő e-mail esetén a meglévő user profilját frissíti;
- új e-mail esetén Auth usert hoz létre automatikus meghívó/reset e-mail nélkül;
- ideiglenes technikai jelszót nem tárol és nem jelenít meg;
- az import után az admin userenként küldhet jelszó-visszaállító linket.

Az Auth API és az alkalmazás adatbázisa közötti művelet nem egyetlen PostgreSQL-tranzakció. Emiatt minden sor külön biztonságosan feldolgozott egység, a részleges hibát az admin felület egyértelműen jelzi. A sikeres profilváltozások auditáltak.

## Jelszó-visszaállítás adminból

Az admin aktív userenként külön `Jelszó-visszaállító link küldése` műveletet kap.

Szabályok:
- csak aktív admin indíthatja;
- csak aktív usernek küldhető;
- a cím a profil hitelesített e-mail címe;
- jelszó, reset token és reset URL nem kerül audit payloadba vagy alkalmazásadatbázisba;
- az admin művelet auditálva van;
- a tényleges jelszóbeállítás a meglévő Supabase recovery folyamaton történik.

## Admin felület egyszerűsítése

A hozzáférési csoportok nem részei a cél üzleti modellnek. A helyiségjogok explicit, userenkénti jogosultságok.

A Tréningterem külön admin-checkboxa megszűnik. Egyetlen Tréningterem van, a speciális üzleti szabályokat stabil rendszerazonosítás kezeli.

A más foglalók nevének láthatósága globális beállítás, nem userenkénti kapcsoló. Alapállapotban a nevek láthatók; kikapcsolva más user foglalásánál csak a foglaltság látható, a saját foglalás felismerhető, admin számára az adminisztrációs név látható marad.

## Admin foglalás más user nevében

Admin foglalási ablakban aktív felhasználó választható. A foglalás tulajdonosa a kiválasztott user, az audit `actor_user_id` értéke a végrehajtó admin.

Normál user sem kliens-, sem backend-oldalon nem adhat meg tetszőleges másik `user_id`-t.
