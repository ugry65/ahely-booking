# Állapotmentés – 2026-08-21 – Foglalási naptár és foglaláskezelés

Ez a dokumentum a 2026-08-21-én kézzel UAT-olt, működő állapot regresszióvédett pillanatképe. Új fejlesztési fázis vagy új beszélgetés előtt ezt a fájlt a `docs/BOOKING_UI_UX_BASELINE.md`, a `docs/CALENDAR_BOOKING_MANAGEMENT.md`, a projektkontextus és az aktuális funkcionális specifikáció mellett kötelező figyelembe venni.

## 1. Naptár alap-UX – megőrzendő

- A foglalási naptár Skedda/AllBooked-szerű, mobilon kompakt napi nézetet használ.
- Mobilon felül 7 napos dátumsáv látszik, külön naptárválasztóval.
- A naptár időtartománya 07:00–22:00.
- A bal oldali órasáv vízszintes görgetésnél sticky/fix marad.
- Az egész órák vízszintes rácsvonalai jól láthatók, az óraszámok ezekhez igazodnak.
- Mobilon a naptár normál érintéses görgetése nem indít foglalást.
- Mobilon foglalási kijelölés long-press után indul.
- A kijelölt időszak után a foglalási modal automatikusan megnyílik.
- A jobb alsó `+` gomb közvetlen új foglalást indít.
- A felső mobil hamburger menü menüpont választásakor automatikusan bezár.
- A Tréningterem neve a naptár fejlécében csak egyszer jelenik meg.

## 2. Mentetlen kijelölés viselkedése – 2026-08-21 UAT PASS

- A zöld `Új foglalás` blokk kizárólag kliensoldali ideiglenes kijelölés.
- Nem számít foglalásnak, amíg a backend mentése nem sikeres.
- Ha a foglalási modal mentés nélkül bezárul, a kijelölés kötelezően eltűnik.
- Ez igaz az X gombra, a `Mégse` gombra és a modal hátterére koppintásra/kattintásra is.
- A mentetlen kijelölés oldalfrissítés vagy következő művelet után sem jelenhet meg valódi foglalásként.

## 3. Foglaló nevének megjelenítése – 2026-08-21 UAT PASS

- Saját foglalásnál a naptár `Saját foglalás` jelölést mutat.
- Más felhasználó aktív foglalásánál a foglaló neve látható, ha az aktuális user `other_booker_names_visible=true` beállítású.
- Ha az admin ezt a láthatóságot letiltja, akkor csak `Foglalt` jelenik meg.
- Az UAT User A baseline beállítása: `other_booker_names_visible=true`.
- Az UAT bootstrap ezt az értéket nem állíthatja vissza `false`-ra.

## 4. Naptárból elérhető foglaláskezelés – megőrzendő

Saját, kezelhető foglalásra koppintva/kattintva műveleti menü jelenik meg:

- `Szerkesztés`
- `Duplikálás`
- `Törlés`

Normál user csak saját foglalását kezelheti. Admin bármely foglalást kezelhet.

### Duplikálás

- Az eredeti foglalás dátum/idő/helyiség/használat/megjegyzés adatai előtöltődnek.
- A másolat mentés előtt módosítható.
- A duplikálás új foglalást hoz létre; az eredeti rekordot nem módosítja.

### Egyszeri foglalás szerkesztése és törlése

- Egyszeri foglalás közvetlenül szerkeszthető.
- Törlés megerősítő lépéssel történik.
- Fizikai adatbázis-törlés nincs; a foglalás története/auditja megmarad.

## 5. Ismétlődő sorozatok kezelése – megőrzendő

Ismétlődő foglalás szerkesztése vagy törlése előtt a rendszer mindig hatókört kér, Skedda/AllBooked-szerűen:

1. `Csak ezt az alkalmat`
2. `Ezt és az ezt követő alkalmakat`
3. `A teljes sorozatot`

A már lezajlott alkalmak történeti adatait sorozatművelet nem írhatja át és nem törölheti.

A backend oldali sorozatművelet:

- atomikus/tranzakciós;
- auditált;
- idempotens;
- nem végez fizikai booking-törlést;
- minden érintett bookingra külön auditnyomot tart fenn.

## 6. Ismétlődő foglalási jogosultság baseline

### Normál user

- Minden normál szobában, amelyhez foglalási joga van, ismétlődő foglalást is létrehozhat.
- Normál szobák alap előrefoglalási limitje 90 nap.
- A normál előrefoglalási limit admin által állítható.
- Tréningteremben normál user ismétlődő foglalást nem hozhat létre.
- A Tréningterem egyszeri foglalásának külön előrefoglalási limitje admin által állítható.

### Admin

- Adminra a normál user előrefoglalási és ismétlődési korlátozásai nem vonatkoznak.
- Admin bármely helyiségben hozhat létre egyszeri vagy ismétlődő foglalást.
- Admin a normál user 90 napos, illetve Tréningterem-limitjén túl is létrehozhat sorozatot.

## 7. Adatbiztonsági/read-model baseline

- A publikus naptár read model minimális adatokat szolgáltat.
- A szerkesztéshez szükséges `note`, `series_id`, `updated_at`, `can_manage` mezők külön jogosultságszűrt RPC-ból érkeznek.
- A kezelési metaadat normál usernél kizárólag saját foglalásra érhető el; admin bármely foglalásra megkaphatja.
- A kliensoldali UI nem tekinthető jogosultsági védelemnek; minden módosítási/törlési jogosultságot backend oldalon újra kell ellenőrizni.

## 8. 2026-08-21 UAT és CI állapot

Kézi UAT során igazolt:

- naptár mobil működése és scroll/long-press alapviselkedése;
- sticky bal órasáv;
- mentetlen `Új foglalás` kijelölés eltűnik a modal megszakításakor;
- más user foglalóneve megjelenik az engedélyezett baseline beállítással;
- naptárból foglaláskezelési műveletek működő tesztverzióban elérhetők.

PR #71 aktuális UAT-olt head: `ca6364799440d6dd3254dec9beba0d06a0e36f6c`.

Automatikus ellenőrzések ezen a headen:

- Application checks: PASS
- Database tests: PASS
- Vercel preview deploy: Ready

## 9. Kötelező regressziós ellenőrzés minden következő naptárfejlesztésnél

Minden naptárt, mobil CSS-t, foglalási modalt, foglalási read modelt vagy booking actiont érintő PR előtt/után ellenőrizni kell legalább:

- bal órasáv sticky maradt-e;
- 07:00 és 22:00 közötti teljes tartomány elérhető-e;
- mobil scroll nem indít-e véletlen foglalást;
- long-press továbbra is működik-e;
- modal megszakítása eltávolítja-e az ideiglenes kijelölést;
- mentés csak sikeres backend tranzakció után eredményez-e valódi blokkot;
- foglaló névláthatósága admin-beállítást követ-e;
- saját foglalás műveleti menüje megmaradt-e;
- szerkesztés/duplikálás/törlés működik-e;
- sorozatnál mindhárom hatókör felajánlásra kerül-e;
- normál user nem kezelheti-e más user foglalását;
- backend jogosultság és ütközésvédelem továbbra is aktív-e;
- auditnapló megmarad-e.

## 10. Regresszióvédelmi szabály

A fenti működésből semmit nem szabad egy új feature kedvéért csendben eltávolítani vagy egyszerűsíteni. Ha egy jövőbeli üzleti döntés szándékosan megváltoztatja valamelyik pontot, akkor ugyanabban a PR-ban frissíteni kell ezt a snapshotot vagy az utód baseline dokumentumot, és egyértelműen dokumentálni kell, hogy tudatos üzleti döntés történt, nem regresszió.
