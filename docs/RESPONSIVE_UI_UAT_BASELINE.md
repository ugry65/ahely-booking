# Responsive UI/UAT baseline

Dátum: 2026-08-21

## Cél

Ez a dokumentum tartós regresszióvédelmi baseline az A-Hely foglalási rendszer felületéhez. Új UI-fejlesztés vagy meglévő UI módosítása nem tekinthető késznek kizárólag egyetlen képernyőméreten végzett ellenőrzés alapján.

## Kötelező UAT nézetek

Minden UI-t érintő változtatásnál három külön megjelenést kell ellenőrizni:

1. **Mobil portrait**
   - A jelenleg mobilon elfogadott foglalási felület referencia/baseline.
   - Már elfogadott mobil viselkedést új fejlesztés nem ronthat el.

2. **Tablet landscape**
   - Önálló UAT-kategória, nem tekinthető automatikusan desktop nézetnek.
   - Külön ellenőrizendő a naptár, vízszintes és függőleges görgetés, sticky/fix elemek, helyiségfejlécek, időoszlop, modalok és menük.

3. **Laptop / desktop**
   - Külön regressziós ellenőrzés szükséges.
   - Ellenőrizendő, hogy mobilra vagy tabletre készített CSS/breakpoint változás ne okozzon túlméretezett elemeket, hibás tördelést, indokolatlan egymás alá rendezést vagy hibás sticky/fix viselkedést.

## Kiemelt naptár-regressziós pontok

A naptáras felületnél különösen védeni kell a már elfogadott működést:

- bal oldali időoszlop és az órák igazítása;
- egész órákat jelző vízszintes vonalak;
- félórás rács és foglalási pozicionálás;
- bal időoszlop megfelelő fix/sticky viselkedése;
- helyiségfejlécek és azok vízszintes együttmozgása;
- mobilon használható vízszintes és függőleges görgetés;
- teljes napi időtartomány elérhetősége görgetéssel;
- foglalási blokkok pontos helye és mérete;
- saját és más felhasználó foglalásának megjelenítése;
- új, még el nem mentett foglalás ne maradjon bent tényleges foglalásként;
- foglalás szerkesztési, duplikálási és törlési menük/modalok használhatósága;
- ismétlődő foglalásnál az egy alkalom / ettől kezdve / teljes sorozat műveleti választás;
- mobil böngésző saját kezelősávjai mellett is használható görgetés és kezelőszervek.

## Elfogadott időoszlop- és órarács-megjelenés

Állapot: **UAT PASS, regresszióvédett – 2026-08-21**.

Mobil portrait, iPad/tablet landscape és laptop/desktop nézetben egységesen megőrzendő:

- az óracímkék az adott órasáv belsejében, középre igazítva jelennek meg;
- az egész órás vonal erősebb, a félórás vonal finomabb;
- az egész órás vonal a bal időoszlop szélétől megszakítás nélkül fut, és pontosan folytatódik a helyiségoszlopokban;
- a bal oldali vonal nem lehet az egész órás helyiségoldali vonalhoz képest függőlegesen elcsúszva;
- az időoszlop vonalai és a helyiségoldali rács ugyanazt a percalapú koordinátageometriát használják;
- a bal időoszlop vízszintes görgetésnél sticky marad;
- érintőképernyőn a naptári kijelölés nem indíthat natív iOS/Safari szövegkijelölést.

Elfogadott implementációs referencia: PR #74, commit `fd87b8e1c4f4304cf9b653dcd73fbdaab7e266f2` és az ezt követő dokumentációs commitok. A megjelenés későbbi verzióból külön dokumentált üzleti/UI döntés nélkül nem távolítható el és nem egyszerűsíthető vissza.

## Onboarding UI jelenlegi elfogadott szerkezete

Az első belépéskori adatkitöltésnél megőrzendő:

- Vezetéknév;
- Keresztnév;
- E-mail;
- Telefonszám;
- Számla típusa: Magánszemély / Vállalkozó;
- `A számlázási név megegyezik a nevemmel` opció;
- Számlázási név;
- külön **Számlázási cím** szekció, alatta:
  - Irányítószám,
  - Település,
  - Utca,
  - Házszám;
- vállalkozói számlázásnál az adószám kötelező.

A címmezők előtt nem kell minden esetben megismételni a `Számlázási` szót, mert ezt a `Számlázási cím` szekciócím egyértelművé teszi.

## Fejlesztési szabály

UI-változtatás előtt meg kell vizsgálni a jelenlegi implementációt és a regressziós kockázatot. A javítás lehetőleg breakpoint-specifikus legyen, ha a probléma csak egy adott eszközkategóriát érint.

A már elfogadott mobil baseline-t nem szabad egy tablet/desktop javítás kedvéért általános CSS-változtatással felülírni, ha ugyanaz célzott breakpointtal biztonságosan megoldható.

## Definition of Done UI-változtatásnál

Egy UI-t érintő fejlesztés csak akkor tekinthető késznek, ha:

- az automatikus alkalmazás- és releváns regressziós tesztek sikeresek;
- mobil portrait ellenőrzés megtörtént;
- tablet landscape ellenőrzés megtörtént;
- laptop/desktop ellenőrzés megtörtént;
- a korábbi `BOOKING_UI_UX_BASELINE.md` követelményei nem sérültek;
- nincs ismert regresszió a foglalási üzleti logikában vagy jogosultságokban;
- staging UAT után kerülhet production irányba.

## Forrásprioritás

- Forráskód hiteles forrása: GitHub repository.
- Üzleti/funkcionális szabályok: aktuális FS és projekt dokumentáció.
- Korábbi elfogadott UI: `docs/BOOKING_UI_UX_BASELINE.md` és ez a responsive baseline.
- Új fejlesztés nem törölhet vagy írhat felül korábban elfogadott funkciót dokumentált döntés nélkül.
