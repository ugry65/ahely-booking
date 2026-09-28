# Fejlesztési napló és döntések – 2026-09-28

Ez a dokumentum a 2026-09-28-i fejlesztési munkát, üzleti döntéseket, staging kísérleteket és production változásokat rögzíti. Célja, hogy a következő fejlesztési beszélgetés a teljes chat-előzmény nélkül is biztonságosan folytatható legyen.

## 1. Saját naptárszín – elkészült és productionben van

- A felhasználó saját naptárszínt választhat az Adataim oldalon.
- 20 előre definiált szín használható; ugyanazt a színt több user is választhatja.
- A választott szín globális megjelenítési preferencia, üzleti/jogosultsági/pénzügyi logikát nem befolyásol.
- A meglévő profiles.calendar_color mező maradt az authoritative tároló.
- Issue #252, PR #253.
- update_own_calendar_color(text, uuid) SECURITY DEFINER RPC csak az engedélyezett palettát fogadja el, aktív saját profilra ír és auditot készít.
- Staging UAT során az authenticated calendar_color SELECT jogosultság hiányzott; célzott GRANT javította, a profiles RLS változatlan maradt.
- CI PASS; PR #253 squash merge release commit: 4ce6f60f…
- Explicit jóváhagyással production migrációk: user_calendar_color_self_service; allow_own_calendar_color_read.
- Production utóellenőrzés: calendar_color SELECT és RPC execute rendben, profiles RLS változatlan.

## 2. Havi elszámolási összesítő – új üzleti igény

### Normál felhasználók
- Tervezett mezők: Összes óra, Fizetendő, Befizetve, Tartozás, Fizetési állapot/Fizetve.
- A Fizetve nem lehet tartós boolean: ha később új elszámolandó foglalás keletkezik ugyanabban a hónapban, új tartozásnak kell megjelennie.
- Részfizetés külön befizetés-rögzítést igényel.

### Alkalmi Csoport / Alkalmi Egyéni
- Gyűjtőfelhasználók; nem helyes a teljes havi gyűjtősort egy ügyfélként kezelni.
- A tényleges alkalmi foglaló neve a booking_title / Foglalás címe adatból származik.
- Ugyanazon hónap + gyűjtőuser + azonos foglalónév egy összesített sor.
- Mutatandó: alkalmak száma, összes óra, fizetendő; a név lenyitható az egyedi bookingokra.
- Az egyedi alkalmak fizetettségének külön kezelhetőnek kell lennie; a név szerinti havi státusz ezek összegzéséből származik.
- Példa: két 45 000 Ft-os alkalomból egy rendezett → 90 000 Ft fizetendő, 45 000 Ft befizetve, 45 000 Ft tartozás, Részben fizetve.
- Issue #254 rögzíti a scope-ot.

## 3. Staging UI prototípus – elkészült, NEM production feature

- Branch: feat/casual-settlement-summary; PR #255.
- Külön Alkalmi foglalók elszámolása blokk.
- Felismeri az Alkalmi Csoport, Alkalmi Egyéni és régi staging Csoport A. / A. Csoport neveket.
- booking_title szerint összevon; alkalomszám, óra, fizetendő; lenyitható egyedi dátum/helyiség/idő/összeg.
- Befizetve, Tartozás, Fizetve oszlopok UX-helye látható.
- A checkbox szándékosan disabled, pénzügyi adatot nem módosít.
- Projektgazdai staging UAT alapján a megjelenítési irány megfelelő.
- TESZT Fehér Katalin két alkalma egy sorban 18,00 óra / 90 000 Ft, lenyitva két 45 000 Ft-os booking.
- PR #255 prototípus; ne merge-eljük productionbe automatikusan. A pénzügyi fejlesztés a projektgazda kérésére megállt.

## 4. Staging UAT tesztadatok

A stagingben négy, kizárólag teszt célú aktív booking készült a meglévő Csoport A. profilhoz és Tréningteremhez:
- TESZT Fehér Katalin – 2026-09-17 08:00–17:00 – 45 000 Ft
- TESZT Fehér Katalin – 2026-09-18 08:00–17:00 – 45 000 Ft
- TESZT Funza Zsolt – 2026-09-25 09:30–11:30 – 10 000 Ft
- TESZT Solnet solutions – 2026-09-28 09:00–16:00 – 35 000 Ft
- Note mindegyiken: STAGING UAT – alkalmi elszámolás.
- Idempotency key-k: 70000000-0000-0000-0000-000000000001 … 0004.
- Production adat nem került stagingbe és production üzleti adat nem módosult.

## 5. Production-derived staging ötlet – NINCS eldöntve

- Felmerült egyirányú production → staging frissítés külön staging Auth-tal, semlegesített e-mail-címekkel, blokkolt külső kommunikációval és megtartott üzleti kapcsolatokkal.
- Staging soha nem írhatna vissza productionbe.
- Ez eltér a korábbi production-adat másolása nélküli elvtől, ezért architekturális/adatvédelmi döntést igényel.
- A projektgazda később gondolja át. Nincs engedély production adatok stagingbe másolására.

## 6. Befizetések – jelenlegi adatmodell és mai határ

- Már létezik: monthly_settlements, payments, settlement_booking_lines, admin_record_payment(...).
- A jelenlegi payment modell settlement-szintű; alkalmi booking-szintű payment allocation külön adatmodell nélkül nem vezethető megbízhatóan.
- Felmerült userenként alapértelmezett fizetési mód/célhely, de ezt a projektgazda elvetette a foglalási rendszer jelenlegi scope-jából, mert a külön pénzügyi feldolgozó kezeli és nem kíván duplikált információt.
- User-default payment method/destination NEM készül.
- A befizetés/fizetettség további fejlesztése most megállt.

## 7. Következő folytatási pont

1. Naptárszín productionben kész.
2. Alkalmi elszámolási UI staging prototípus működik, de checkbox nem ír pénzügyi adatot.
3. Normál userek működő Fizetve checkboxa nincs implementálva.
4. Booking-szintű alkalmi payment allocation nincs implementálva.
5. Production-derived staging nincs jóváhagyva/implementálva.
6. Payment method/destination user-default nincs scope-ban.
7. Pénzügyi fejlesztést a projektgazda kérésére itt meg kell állítani.

Production pénzügyi adatbázis-módosítás az elszámolási prototípus miatt nem történt.