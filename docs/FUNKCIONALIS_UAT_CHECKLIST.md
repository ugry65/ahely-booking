# A-Hely foglalási rendszer – Funkcionális UAT checklist

Verzió: 1.1
Dátum: 2026-08-26
Kapcsolódó issue-k: #32, #82
Kanonikus funkcionális forrás: `docs/CURRENT_FUNCTIONAL_BASELINE.md`

## 1. Cél

A checklist célja annak bizonyítása, hogy a jelenlegi rendszer a Skedda kiváltásához szükséges napi foglalási működést és a kanonikus baseline-ban elfogadott admin/pénzügyi funkciókat végponttól végpontig, felhasználói szemmel helyesen biztosítja.

Ez a dokumentum a 2026-08-22–26 között elkészült funkciókkal kibővített UAT-készlet. Production indulás előtt továbbra is kötelező a backup/restore automatizálás, sikeres restore-drill, production monitoring/alert teszt és minden production blocker lezárása.

A Befizetések UI nem aktív scope. Automatikus booking confirmation e-mail nem go-live blocker.

## 2. Tesztelési elv

Minden tesztesethez háromféle bizonyíték tartozhat:
- **Automatikus:** meglévő Vitest, pgTAP vagy konkurenciateszt;
- **Kódszintű:** az implementáció jelen van, de böngészős működés még nem bizonyított;
- **Manuális UAT:** valódi böngészős használattal ellenőrizendő.

Státuszok:
- `NEM FUTOTT`
- `SIKERES`
- `HIBÁS`
- `BLOKKOLT`

Hiba súlyossága:
- **P1:** adatvesztés, jogosulatlan hozzáférés, dupla foglalás, pénzügyileg hibás elszámolás vagy a rendszer alapvető használhatatlansága;
- **P2:** lényeges üzleti szabály hibás, vagy a normál napi működés érdemben akadályozott;
- **P3:** kisebb UX, szövegezési vagy kényelmi probléma.

A production-funkcionális kapu akkor teljesül, ha nincs nyitott P1/P2 funkcionális hiba vagy production blocker.

## 3. Tesztkörnyezet és tesztadat

A manuális UAT staging környezetben fut, nem production adaton.

Szükséges minimum tesztidentitások:
1. `ADMIN-1`: aktív admin;
2. `ADMIN-2`: második aktív admin az utolsó-admin védelemhez;
3. `USER-A`: aktív normál user, több helyiséghez foglalási és ismétlési joggal;
4. `USER-B`: aktív normál user, eltérő helyiségjogokkal;
5. `USER-HIDDEN`: aktív user a privacy teszthez;
6. `USER-INACTIVE`: inaktív user;
7. `USER-NEW`: onboarding előtt álló új user;
8. `USER-FREE`: Free pricing;
9. `USER-FIXED`: Fix óradíj tesztuser, amikor az admin UI/RPC elkészült.

Szükséges tesztkonfiguráció:
- legalább 2 normál helyiség;
- Tréningterem;
- egy user által nem foglalható helyiség;
- eltérő room-group és közvetlen `can_repeat` jogok;
- legalább egy teszthónap pricing és settlement vizsgálathoz.

## 4. Belépés, onboarding és felhasználói életciklus

### UAT-AUTH-01 – Sikeres belépés
**Elvárt eredmény:** sikeres belépés; foglalási felület; user neve helyes; admin menüpont nincs normál usernél.

### UAT-AUTH-02 – Hibás jelszó
**Elvárt eredmény:** nincs belépés; magyar hibaüzenet; érzékeny technikai adat nem jelenik meg.

### UAT-AUTH-03 – Inaktív user
**Elvárt eredmény:** védett funkciók közvetlen URL/API manipulációval sem használhatók.

### UAT-AUTH-04 – Kijelentkezés
**Elvárt eredmény:** session megszűnik; védett oldal belépésre visz.

### UAT-AUTH-05 – Jelszó-visszaállítás
**Elvárt eredmény:** reset flow működik; hibás/lejárt link érthetően kezelve.

### UAT-ONBOARD-01 – Onboarding blokkolás
**Lépések:** USER-NEW állítson jelszót, de ne fejezze be az adatkitöltést.
**Elvárt eredmény:** normál user nem használhatja a foglalási felületet; onboarding oldalra kerül. Adminra ez nem vonatkozik.

### UAT-ONBOARD-02 – Kötelező számlázási adatok
**Elvárt eredmény:** telefon, számlatípus, számlázási név/cím kötelező; vállalkozónál adószám nélkül nincs sikeres befejezés; magánszemélynél nem kötelező.

### UAT-ONBOARD-03 – Név átvétele és sikeres befejezés
**Elvárt eredmény:** „számlázási név megegyezik” opció helyesen kitölt; sikeres mentés után foglalási rendszer elérhető; `onboarding_completed_at` jellegű állapot rögzül.

### UAT-IMPORT-01 – CSV user import
**Előkészítés:** `last_name,first_name,email` oszlopokat tartalmazó CSV.
**Elvárt eredmény:** új userek létrejönnek aktiváló levél automatikus kiküldése nélkül; számlázási adatot nem kell importálni.

### UAT-IMPORT-02 – CSV duplikált és meglévő e-mail
**Elvárt eredmény:** fájlon belüli duplikált e-mail hibás; már létező e-mail biztonságosan kihagyott/egyértelműen jelzett; nincs duplikált auth/profile.

## 5. Naptár és alap használhatóság

### UAT-CAL-01 – Napi többhelyiséges naptár
**Elvárt eredmény:** jogosult helyiségek oszlopokban; 07:00–22:00; saját foglalás elkülönül; névláthatóság szabályos.

### UAT-CAL-02 – Dátumváltás
**Elvárt eredmény:** kiválasztott nap foglalásai jelennek meg.

### UAT-CAL-03 – Nem foglalható helyiség
**Elvárt eredmény:** UI-ban nem választható; közvetlen manipulációval sem foglalható.

### UAT-CAL-04 – Globális névláthatóság és stabil szín
**Lépések:** globális névláthatóság BE/KI állapotának ellenőrzése USER-A, másik user és admin szemszögből.
**Elvárt eredmény:** kikapcsolva más user neve és stabil színe sem szivárog ki normál usernek; saját foglalás felismerhető; admin látja az adminisztrációhoz szükséges identitást.

### UAT-COLOR-01 – Stabil user-szín
**Elvárt eredmény:** ugyanazon user színe újratöltés és új session után változatlan; privacy kikapcsolásnál nem használható más user azonosítására.

## 6. Egyedi foglalás

### UAT-BOOK-01 – Normál sikeres foglalás
**Elvárt eredmény:** pontosan egy booking; naptárban és Foglalásaimban megjelenik; adatok helyesek.

### UAT-BOOK-02 – 90 perces foglalás
**Elvárt eredmény:** sikeres 10:00–11:30.

### UAT-BOOK-03 – Minimum 1 óra
**Elvárt eredmény:** 30 perc elutasított; nincs rekord.

### UAT-BOOK-04 – 30 perces rács
**Elvárt eredmény:** UI és backend is kikényszeríti.

### UAT-BOOK-05 – Nyitvatartás
**Elvárt eredmény:** 07:00 előtt / 22:00 után elutasított.

### UAT-BOOK-06 – Minden naptári nap foglalható
**Elvárt eredmény:** nincs általános zárt nap; egyéb szabályok érvényesek.

### UAT-BOOK-07 – Előrefoglalási limit
**Elvárt eredmény:** user limitjén belül engedélyezett, túl elutasított.

### UAT-BOOK-08 – Átfedő foglalás
**Elvárt eredmény:** második elutasított; első változatlan.

### UAT-BOOK-09 – Egymáshoz érő foglalások
**Elvárt eredmény:** 10–11 után 11–12 sikeres.

### UAT-BOOK-10 – Két egyidejű foglalási kísérlet
**Elvárt eredmény:** maximum egy sikeres. Automatizált konkurenciateszt kötelező.

### UAT-BOOK-11 – Idempotens újraküldés
**Elvárt eredmény:** nem jön létre duplikált booking.

### UAT-BOOK-12 – Sikeres/sikertelen UI-visszajelzés
**Elvárt eredmény:** sikeres booking egyértelműen visszajelzett és azonnal megjelenik; sikertelen booking nem jelenik meg sikeresként. Booking confirmation e-mail hiánya nem hiba.

### UAT-BOOK-13 – Foglalás címe
**Elvárt eredmény:** megadott `Foglalás címe` mentődik és jogosult admin riportban később visszakereshető.

## 7. Tréningterem

### UAT-TRAIN-01 – Normál user előrefoglalási limit
**Elvárt eredmény:** beállított default/egyedi limit érvényesül.

### UAT-TRAIN-02 – Egyéni/csoportos használat
**Elvárt eredmény:** Tréningteremnél mindkettő; normál szobán nincs group selector.

### UAT-TRAIN-03 – Ismétlődő Tréningterem normál userként
**Elvárt eredmény:** elutasított.

### UAT-TRAIN-04 – Ismétlődő Tréningterem adminként
**Elvárt eredmény:** engedélyezett.

### UAT-TRAIN-05 – Csoportos default 5000 Ft és admin override
**Lépések:** admin foglaljon Csoportos Tréningtermet; ellenőrizze 5000 Ft defaultot; írja át pl. 7500 Ft-ra.
**Elvárt eredmény:** mentett booking a választott díjjal számolódik; havi részletezésben helyesen jelenik meg.

### UAT-TRAIN-06 – Atomi booking + egyedi díj
**Bizonyíték:** automatizált rollback teszt kötelező.
**Elvárt eredmény:** díjrögzítési hiba esetén booking/sorozat sem marad félkész állapotban.

## 8. Saját foglalás módosítása és duplikálása

### UAT-EDIT-01 – Sikeres módosítás
**Elvárt eredmény:** régi idő felszabadul; új egyszer jelenik meg.

### UAT-EDIT-02 – Ütköző módosítás
**Elvárt eredmény:** elutasított; eredeti megmarad.

### UAT-EDIT-03 – Jogosulatlan helyiség
**Elvárt eredmény:** elutasított.

### UAT-EDIT-04 – 24 órán belüli módosítás
**Elvárt eredmény:** normál usernek elutasított.

### UAT-EDIT-05 – Párhuzamos módosítás
**Elvárt eredmény:** elavult optimistic-concurrency kérés nem ír felül frissebb állapotot.

### UAT-EDIT-06 – Duplikálás
**Lépések:** meglévő booking → Duplikálás → új időpont.
**Elvárt eredmény:** új booking előtöltött releváns adatokkal készíthető; eredeti booking változatlan; minden foglalási szabály újra érvényesül.

## 9. Lemondás

### UAT-CANCEL-01 – Saját foglalás 24 órán túl
**Elvárt eredmény:** sikeres; aktív naptárból eltűnik; idő felszabadul; audit/történet megmarad.

### UAT-CANCEL-02 – Saját foglalás 24 órán belül
**Elvárt eredmény:** elutasított.

### UAT-CANCEL-03 – Sorozat egy alkalma
**Elvárt eredmény:** csak az adott alkalom törlődik/lemondódik.

### UAT-CANCEL-04 – Admin törlés
**Elvárt eredmény:** bármikor; auditált; havi aktív elszámolásból kizárt.

## 10. Ismétlődő foglalások

### UAT-REC-01 – Heti sorozat darabszámmal
### UAT-REC-02 – Kétheti sorozat
### UAT-REC-03 – Napi sorozat
### UAT-REC-04 – Havi sorozat
### UAT-REC-05 – Végdátum
### UAT-REC-06 – Kivételdátum
### UAT-REC-07 – `abort_all`
### UAT-REC-08 – `create_available`
### UAT-REC-09 – DST-váltás

Az elvárt működés a kanonikus baseline szerint: helyi kezdési idő megőrzése, kivételdátum kihagyása, ütközésnél választott policy szerinti atomikus vagy részleges létrehozás.

### UAT-REC-10 – Sorozat scope műveletek
**Elvárt eredmény:** aktuális alkalom / ettől kezdve / teljes sorozat user-facing scope-ok elérhetők és a dokumentált backend szemantikát követik.
**Megjegyzés:** a rekord-szintű pontos scope-dokumentáció production előtt külön lezárandó dokumentációs tétel.

## 11. Admin – felhasználók, helyiségek és hozzáférések

### UAT-ADMIN-01 – Admin menü jogosultság
### UAT-ADMIN-02 – User létrehozás és aktiváló link
### UAT-ADMIN-03 – User aktiválás/inaktiválás
### UAT-ADMIN-04 – Helyiség kezelés
### UAT-ADMIN-05 – Közvetlen user-helyiségjog
### UAT-ADMIN-06 – Csoportos `can_book`
**Elvárt eredmény:** csoporttagság foglalási jogot ad a konfiguráció szerint.

### UAT-ADMIN-07 – `can_repeat` kizárólag közvetlen jog
**Elvárt eredmény:** csoporttagság önmagában soha nem ad repeat jogot; közvetlen permission igen; Tréningterem normál user repeat továbbra is tiltott.

### UAT-ADMIN-08 – Globális névláthatóság
### UAT-ADMIN-09 – Utolsó admin védelem
**Lépések:** ADMIN-1/ADMIN-2 mellett egy admin lefokozása/deaktiválása megengedett; utolsó aktív admin lefokozása vagy deaktiválása próbálva.
**Elvárt eredmény:** az utolsó admin művelet backendből is elutasított.

## 12. Díjazás és havi elszámolás

### UAT-PRICING-01 – Sávos 20 óra
**Elvárt eredmény:** 20 × 1900 Ft = 38 000 Ft normál díj.

### UAT-PRICING-02 – Progresszív 20 óra
**Elvárt eredmény:** 15 × 2700 + 5 × 1900 = 50 000 Ft.

### UAT-PRICING-03 – Free
**Elvárt eredmény:** minden booking 0 Ft, beleértve Tréningterem Csoportos használatot is; óraszám megmarad.

### UAT-PRICING-04 – Policy effective month
**Elvárt eredmény:** jövőbeli hónapra beállítható; megfelelő hónaptól érvényes; történeti lezárt hónap kontrollálatlanul nem írható át.

### UAT-PRICING-05 – Fix óradíj admin kezelése
**Státusz:** jelenleg **BLOKKOLT production gap**, amíg admin RPC/UI nincs kész.
**Elvárt eredmény a megvalósítás után:** admin userenként és effective month-tal fix óradíjat állít; auditált; normál user nem módosíthatja.

### UAT-PRICING-06 – Fix precedencia
**Elvárt eredmény:** Fix felülírja a tiered/progressive normál díjat; Free a Fixet is; nem-Free Tréningterem Csoportos továbbra is saját speciális díjon számolódik.

### UAT-MONTH-01 – Havi összesítés
**Elvárt eredmény:** aktív foglalások órái és fizetendő összege helyes.

### UAT-MONTH-02 – Lemondott foglalás kizárása
### UAT-MONTH-03 – Hónaphatár Europe/Budapest
### UAT-MONTH-04 – Admin-only hozzáférés
### UAT-MONTH-05 – Foglalás címe a tételes aktív listában
**Elvárt eredmény:** `Foglalás címe` oszlop látszik; Tréningterem admin booking cím visszakereshető.

### UAT-CSV-01 – Összesítő CSV
**Elvárt eredmény:** magyar ékezetek, magyar Excel-kompatibilis óraszám, biztonságos fájlnév.

### UAT-CSV-02 – CSV formula-injection
**Bizonyíték:** automatikus Vitest.

### UAT-CSV-03 – Részletes CSV Foglalás címe
**Elvárt eredmény:** a részletes export tartalmazza a `Foglalás címe` mezőt.

## 13. Settlement és pénzügyi történet

### UAT-SETTLE-01 – Settlement snapshot létrehozása
**Elvárt eredmény:** ugyanazt a központi pricing eredményt snapshotolja, amelyet a havi számítás használ.

### UAT-SETTLE-02 – Snapshot/revision immutabilitás
**Bizonyíték:** automatikus DB teszt kötelező.
**Elvárt eredmény:** történeti revision/booking-line közvetlenül nem írható át vagy törölhető kontrollálatlanul.

### UAT-PAY-01 – Befizetések UI parkoltatva
**Lépések:** admin menü és közvetlen régi `/admin/befizetesek` URL ellenőrzése.
**Elvárt eredmény:** nincs aktív Befizetések menüpont/használható payment UI; közvetlen régi URL biztonságosan átirányít a jóváhagyott admin oldalra. Payment backend megléte nem jelent aktív feature-t.

## 14. Mobil/tablet és UX

Kézi ellenőrzés legalább:
- mobil kb. 390 px;
- tablet 768–1024 px;
- desktop 1280 px+.

### UAT-UX-01 – Mobil naptár
**Elvárt eredmény:** 7 napos sáv, sticky időoszlop, long press, természetes scroll, modal használható.

### UAT-UX-02 – Tablet naptár
### UAT-UX-03 – Magyar szövegek
### UAT-UX-04 – Dupla kattintás / lassú kérés
**Elvárt eredmény:** nincs duplikált üzleti rekord.

### UAT-UX-05 – Ismert mobil scroll hiba ellenőrzése
**Elvárt eredmény:** 07:00–22:00 között folyamatos függőleges scroll; a korábban esetlegesen megfigyelt 18:00 körüli megakadás nem kívánt viselkedés.

## 15. Production infrastruktúra UAT-kapu

Ezek nem a napi booking funkciók részei, de production GO előtt kötelező bizonyítékok:

### UAT-PROD-01 – Backup automatizálás
**Elvárt eredmény:** ütemezett backup ténylegesen létrejön, ellenőrzött, off-platform tárolt.

### UAT-PROD-02 – Restore-drill
**Elvárt eredmény:** backupból külön környezetben helyreáll a DB; booking/jogosultság/audit/settlement konzisztencia PASS.

### UAT-PROD-03 – Monitoring/heartbeat alert drill
**Elvárt eredmény:** kontrollált hibát külső monitor észlel; riasztás ténylegesen megérkezik; recovery jelzés is működik.

## 16. UAT jegyzőkönyv

Minden manuális futásnál rögzítendő:
- dátum;
- környezet és commit SHA;
- tesztelő;
- teszteset ID;
- státusz;
- rövid megjegyzés;
- hiba esetén GitHub issue száma és P1/P2/P3 besorolása.

A `docs/UAT_FUTASI_JEGYZOKONYV.md`-t ezzel a checklist-verzióval szinkronban kell tartani.

## 17. Kilépési feltétel

A rendszer productionre funkcionálisan alkalmasnak csak akkor minősíthető, ha:
1. nincs nyitott P1/P2 vagy production blocker;
2. a kritikus AUTH/ONBOARD/BOOK/EDIT/CANCEL/REC/ADMIN/PRICING/MONTH tesztek sikeresek;
3. a napi naptár mobilon, tableten és desktopon használható;
4. a meglévő automatikus tesztek és CI zöldek ugyanazon elfogadott kódon;
5. a Fix óradíj admin RPC/UI és regressziós tesztje elkészült;
6. backup + restore-drill sikeres;
7. monitoring/alert drill sikeres;
8. a manuális UAT eredménye dokumentált;
9. kritikus független review lezárt;
10. explicit production GO jóváhagyás megszületett.
