# A-Hely foglalási rendszer – Funkcionális UAT checklist

Verzió: 1.0

Dátum: 2026-08-18

Kapcsolódó issue: #32

## 1. Cél

A checklist célja annak bizonyítása, hogy a jelenlegi rendszer a Skedda kiváltásához szükséges napi foglalási működést végponttól végpontig, felhasználói szemmel helyesen biztosítja.

Ez a fázis megelőzi a tényleges production backup/restore automatizálást. Production indulás előtt továbbra is kötelező lesz a napi backup és sikeres restore-drill.

A teljes díjszámítás, befizetés, tartozás, XLSX és pénzügyi modul most nem része az elfogadási tesztnek.

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

- **P1:** adatvesztés, jogosulatlan hozzáférés, dupla foglalás vagy a rendszer alapvető használhatatlansága;
- **P2:** lényeges üzleti szabály hibás, vagy a normál napi működés érdemben akadályozott;
- **P3:** kisebb UX, szövegezési vagy kényelmi probléma.

A Skedda-kiváltási funkcionális kapu akkor teljesül, ha nincs nyitott P1/P2 funkcionális hiba.

## 3. Tesztkörnyezet és tesztadat

A manuális UAT-ot staging környezetben kell futtatni, nem production adaton.

Szükséges minimum tesztidentitások:

1. `ADMIN-1`: aktív admin;
2. `USER-A`: aktív normál user, több helyiséghez foglalási és ismétlési joggal;
3. `USER-B`: aktív normál user, eltérő helyiségjogokkal;
4. `USER-HIDDEN`: aktív user, akinek neve mások számára maszkolt;
5. `USER-INACTIVE`: inaktív user.

Szükséges tesztkonfiguráció:

- legalább 2 normál helyiség;
- Tréningterem;
- egy user által nem foglalható helyiség;
- USER-A és USER-B részben eltérő jogosultságai.

## 4. Belépés és felhasználói életciklus

### UAT-AUTH-01 – Sikeres belépés

**Lépések**
1. Nyisd meg a belépési oldalt.
2. Jelentkezz be USER-A-val.

**Elvárt eredmény**
- sikeres belépés;
- a foglalási felület nyílik meg;
- a user neve helyesen jelenik meg;
- admin menüpontok nem láthatók.

**Bizonyíték:** kódszintű + manuális UAT.

### UAT-AUTH-02 – Hibás jelszó

**Elvárt eredmény**
- nincs belépés;
- magyar, érthető hibaüzenet;
- nincs technikai hiba vagy érzékeny adat a válaszban.

### UAT-AUTH-03 – Inaktív user

**Lépések:** próbálj belépni USER-INACTIVE-ként.

**Elvárt eredmény**
- a védett funkciók nem használhatók;
- közvetlen védett URL megnyitásával sem lehet jogosultságot szerezni.

**Automatikus háttér:** aktív profil- és jogosultságellenőrzések.

### UAT-AUTH-04 – Kijelentkezés

**Elvárt eredmény**
- session megszűnik;
- védett oldal újranyitása belépésre visz.

### UAT-AUTH-05 – Jelszó-visszaállítás

**Lépések**
1. Indíts jelszó-visszaállítást.
2. Nyisd meg a reset linket.
3. Adj meg új jelszót.
4. Jelentkezz be az új jelszóval.

**Elvárt eredmény:** teljes folyamat működik; hibás/lejárt link kezelése érthető.

## 5. Naptár és alap használhatóság

### UAT-CAL-01 – Napi többhelyiséges naptár

**Elvárt eredmény**
- a user számára foglalható helyiségek oszlopokban jelennek meg;
- 07:00–22:00 idősáv áttekinthető;
- saját foglalás vizuálisan elkülönül;
- más foglalások neve a névláthatósági szabály szerint jelenik meg.

**Automatikus háttér:** `010_calendar_ui_support.sql`, `007_booking_visibility.sql`, `008_effective_room_permissions.sql`.

### UAT-CAL-02 – Előző/Ma/Következő nap

**Elvárt eredmény:** a dátumváltás helyes; a kiválasztott nap foglalásai jelennek meg.

### UAT-CAL-03 – Nem foglalható helyiség

**Elvárt eredmény**
- USER-A nem kap olyan helyiséget foglalási választási lehetőségként, amelyhez nincs joga;
- közvetlen manipulációval sem lehet oda foglalni.

### UAT-CAL-04 – Névláthatóság

**Lépések**
1. USER-HIDDEN hozzon létre foglalást.
2. USER-A nézze meg ugyanazt a naptárt.
3. ADMIN-1 is nézze meg.

**Elvárt eredmény:** a maszkolás a jóváhagyott szabály szerint működik; saját foglalás mindig felismerhető.

## 6. Egyedi foglalás

### UAT-BOOK-01 – Normál sikeres foglalás

**Lépések**
1. USER-A válasszon engedélyezett normál szobát.
2. Foglaljon egy jövőbeli napon 09:00–10:00 időre.
3. Frissítse a naptárt és nyissa meg a Foglalásaim oldalt.

**Elvárt eredmény**
- pontosan egy foglalás jön létre;
- a naptárban és Foglalásaim alatt is látszik;
- időpont, helyiség, használattípus és megjegyzés helyes.

**Automatikus háttér:** `003_create_booking_rpc.sql` + konkurenciateszt.

### UAT-BOOK-02 – 90 perces foglalás

**Lépések:** foglalás 10:00–11:30.

**Elvárt eredmény:** sikeres, 90 perces időtartam.

### UAT-BOOK-03 – Minimum 1 óra

**Lépések:** próbálj 30 perces foglalást létrehozni.

**Elvárt eredmény:** elutasítás; nincs adatbázisrekord.

### UAT-BOOK-04 – 30 perces rács

**Elvárt eredmény:** UI csak félórás értékeket ajánl; manipulált nem félórás időpont backend/DB oldalon is elutasított.

### UAT-BOOK-05 – Nyitvatartás előtt/után

**Elvárt eredmény:** 07:00 előtti vagy 22:00 utáni idő nem foglalható.

### UAT-BOOK-06 – Minden naptári nap foglalható

**Elvárt eredmény:** nincs globális zárt nap vagy általános naptári kivételdátum. A user a saját jogosultsága, az előrefoglalási limit, a napi 07:00–22:00 idősáv és a többi foglalási szabály keretein belül bármely naptári napon foglalhat.

**Automatikus háttér:** `017_always_open_calendar.sql`.

### UAT-BOOK-07 – Előrefoglalási limit

**Elvárt eredmény:** user default vagy egyedi limitjén túli dátum elutasított; limiten belüli engedélyezett.

### UAT-BOOK-08 – Átfedő foglalás

**Lépések**
1. USER-A foglalja le ugyanazt a helyiséget 10:00–11:00-ra.
2. USER-B próbáljon 10:30–11:30-ra foglalni.

**Elvárt eredmény:** második foglalás elutasított; első változatlanul megmarad.

**Automatikus háttér:** GiST exclusion constraint + `003_create_booking_rpc.sql`.

### UAT-BOOK-09 – Egymáshoz érő foglalások

**Lépések:** meglévő 10:00–11:00 után foglalj 11:00–12:00-ra.

**Elvárt eredmény:** sikeres; félig nyitott intervallum miatt nem ütközés.

### UAT-BOOK-10 – Két egyidejű foglalási kísérlet

**Elvárt eredmény:** ugyanarra a helyiség/időre két párhuzamos kérésből legfeljebb egy sikeres.

**Bizonyíték:** automatizált konkurenciateszt kötelező; manuálisan nem szükséges reprodukálni.

### UAT-BOOK-11 – Idempotens újraküldés

**Elvárt eredmény:** ugyanaz a kérés/idempotenciakulcs nem hoz létre második foglalást.

## 7. Tréningterem

### UAT-TRAIN-01 – Normál user 10 napos limit

**Lépések**
1. USER-A próbáljon Tréningtermet 10 napon belül foglalni.
2. Próbáljon a limit után foglalni.

**Elvárt eredmény:** első engedélyezett, második elutasított a beállított limit szerint.

### UAT-TRAIN-02 – Egyéni/csoportos használat

**Elvárt eredmény:** mindkét használattípus rögzíthető a jogosult esetekben és helyesen jelenik meg.

### UAT-TRAIN-03 – Ismétlődő Tréningterem normál userként

**Elvárt eredmény:** elutasított.

### UAT-TRAIN-04 – Ismétlődő Tréningterem adminként

**Elvárt eredmény:** az üzleti szabály szerint engedélyezett.

## 8. Saját foglalás módosítása

### UAT-EDIT-01 – Sikeres módosítás

**Lépések:** USER-A módosítson egy 24 órán túl kezdődő egyedi foglalást más időpontra.

**Elvárt eredmény**
- régi időpont felszabadul;
- új időpont egyszer jelenik meg;
- módosított adat megjelenik a naptárban és Foglalásaim alatt.

**Automatikus háttér:** `005_update_booking_rpc.sql`.

### UAT-EDIT-02 – Módosítás ütköző időpontra

**Elvárt eredmény:** elutasított; eredeti foglalás nem vész el.

### UAT-EDIT-03 – Módosítás jogosulatlan helyiségbe

**Elvárt eredmény:** elutasított.

### UAT-EDIT-04 – 24 órán belüli módosítás normál userként

**Elvárt eredmény:** elutasított.

### UAT-EDIT-05 – Párhuzamos módosítás

**Elvárt eredmény:** optimista konkurenciavédelem miatt elavult módosítás nem írhatja felül az újabb állapotot.

## 9. Lemondás

### UAT-CANCEL-01 – Saját foglalás lemondása 24 órán túl

**Elvárt eredmény**
- sikeres;
- foglalás eltűnik az aktív naptárból;
- időpont újra foglalható;
- lemondási/audit információ megmarad.

**Automatikus háttér:** `004_cancel_booking_rpc.sql`.

### UAT-CANCEL-02 – Saját foglalás lemondása 24 órán belül

**Elvárt eredmény:** normál user számára elutasított.

### UAT-CANCEL-03 – Ismétlődő sorozat egy alkalma

**Elvárt eredmény:** az egyedi alkalom lemondható anélkül, hogy a teljes sorozat többi alkalma eltűnne.

### UAT-CANCEL-04 – Admin törlés

**Elvárt eredmény:** admin üzleti szabály szerint bármikor törölhet; törlés auditált és havi óraszámból kizárt.

**Megjegyzés:** a DB-képesség implementált; a böngészős admin végpontot külön ellenőrizni kell. Ha nincs használható admin UI, P2 funkcionális gap issue készül.

## 10. Ismétlődő foglalások

### UAT-REC-01 – Heti sorozat darabszámmal

**Elvárt eredmény:** a megadott számú alkalom jön létre ugyanazon helyi kezdési idővel.

### UAT-REC-02 – Kétheti sorozat

**Elvárt eredmény:** 14 napos ritmus.

### UAT-REC-03 – Napi sorozat

**Elvárt eredmény:** napi ritmus, üzleti korlátokon belül.

### UAT-REC-04 – Havi sorozat

**Elvárt eredmény:** eredeti naptári nap követése; rövidebb hónapban dokumentált hónapvégi szabály.

### UAT-REC-05 – Végdátum

**Elvárt eredmény:** végdátum után nincs alkalom.

### UAT-REC-06 – Kivételdátum

**Elvárt eredmény:** kivételdátum nem hoz létre foglalást; a többi alkalom változatlan.

### UAT-REC-07 – `abort_all`

**Elvárt eredmény:** egyetlen ütközés esetén az egész új sorozat visszagörget; részleges sorozat nem marad.

### UAT-REC-08 – `create_available`

**Elvárt eredmény:** szabad alkalmak létrejönnek; ütközők dokumentáltan kimaradnak; eredmény érthetően látható.

### UAT-REC-09 – DST-váltás

**Elvárt eredmény:** helyi kezdési idő nem tolódik el téli/nyári időszámítás váltásakor.

**Automatikus háttér:** `009_recurring_booking_rpc.sql`, `012_recurring_booking_ui_support.sql`, konkurenciateszt.

## 11. Admin – felhasználók, helyiségek és hozzáférések

### UAT-ADMIN-01 – Admin menü jogosultság

**Elvárt eredmény:** ADMIN-1 látja; USER-A közvetlen URL-lel sem fér hozzá.

### UAT-ADMIN-02 – User meghívás/létrehozás

**Elvárt eredmény:** új user létrehozható a jóváhagyott meghívásos folyamattal; nincs nyilvános regisztráció.

### UAT-ADMIN-03 – User aktiválás/inaktiválás

**Elvárt eredmény:** státuszváltás érvényesül a következő hozzáférésnél.

### UAT-ADMIN-04 – Helyiség létrehozás/módosítás/deaktiválás

**Elvárt eredmény:** admin kezelheti; deaktivált helyiség új foglalásra nem használható; történeti adatok megmaradnak.

### UAT-ADMIN-05 – Közvetlen user-helyiségjog

**Elvárt eredmény:** változtatás után a user foglalási lehetősége azonnal a jóváhagyott szabály szerint változik.

### UAT-ADMIN-06 – Csoportos jogosultság

**Elvárt eredmény:** csoporttagság és csoport-helyiségjog effektív jogosultságként érvényesül.

### UAT-ADMIN-07 – User-szintű ismétlődési jog

**Elvárt eredmény:** repeat jog nélkül normál user egyik foglalható normál helyiségben sem indíthat sorozatot; repeat joggal minden effektíven foglalható normál helyiségben indíthat, Tréningteremben viszont normál user továbbra sem. Adminra ez a normál user korlátozás nem vonatkozik.

### UAT-ADMIN-08 – Névláthatóság kapcsolása

**Elvárt eredmény:** a naptár-read model az új globális beállítást követi; kikapcsolva más user neve és stabil színe sem szivárog ki normál usernek.

## 12. Havi óraszám és CSV

### UAT-MONTH-01 – Havi összesítés

**Előkészítés:** USER-A-nak legyen a hónapban 60 és 90 perces aktív foglalása.

**Elvárt eredmény:** 2 foglalás, 150 perc, 2,50 óra.

**Automatikus háttér:** `014_monthly_hours_export.sql`.

### UAT-MONTH-02 – Lemondott foglalás kizárása

**Elvárt eredmény:** lemondott foglalás nem növeli a havi óraszámot.

### UAT-MONTH-03 – Hónaphatár

**Elvárt eredmény:** Europe/Budapest helyi hónap szerint számol.

### UAT-MONTH-04 – Admin-only hozzáférés

**Elvárt eredmény:** normál vagy inaktív user sem oldalon, sem export URL-en nem fér hozzá.

### UAT-CSV-01 – CSV letöltés

**Elvárt eredmény**
- Excelben közvetlenül megnyitható;
- magyar ékezetek helyesek;
- oszlopok és számértékek helyesek;
- biztonságos fájlnév.

### UAT-CSV-02 – CSV formula-injection

**Bizonyíték:** automatikus Vitest; manuális ellenőrzés opcionális.

## 13. Mobil/tablet és UX

A napi foglalási naptár használhatóságát legalább az alábbi viewportokon kell kézzel ellenőrizni:

- mobil kb. 390 px szélesség;
- tablet kb. 768–1024 px;
- desktop 1280 px vagy szélesebb.

### UAT-UX-01 – Mobil naptár

**Elvárt eredmény:** oldal nem törik; a többhelyiséges naptár elérhető/görgethető; foglalási űrlap használható.

### UAT-UX-02 – Tablet naptár

**Elvárt eredmény:** alap napi feladatok kényelmesen elvégezhetők.

### UAT-UX-03 – Magyar szövegek

**Elvárt eredmény:** user felületen nincs fejlesztői angol hiba, SQL/stack trace vagy értelmezhetetlen technikai szöveg.

### UAT-UX-04 – Dupla kattintás / lassú kérés

**Elvárt eredmény:** ismételt submit nem eredményez duplikált üzleti rekordot.

## 14. Kifejezetten ellenőrzendő potenciális funkcionális gap-ek

A kódszintű áttekintés alapján ezekre a manuális UAT során külön figyelni kell:

1. **Admin foglaláskezelés:** az adatbázis admin módosítás/törlés képessége implementált, de ellenőrizni kell, hogy a jelenlegi UI-ból egy admin más user foglalását ténylegesen kényelmesen tudja-e kezelni.
2. **Admin nevében / user számára történő foglalás:** ellenőrizni kell, szükséges-e a Skedda-kiváltáshoz, és ha igen, van-e hozzá teljes UI-folyamat.
3. **Heti nézet:** a jelenlegi implementációs terv szerint még nincs kész. Nem blokkoló, ha a jóváhagyott Skedda-kiváltási minimum a napi többhelyiséges nézet; üzleti UAT során döntendő.
4. **E-mail visszaigazolás:** outbox-adatmodell van, de a worker/retry a backlog szerint nincs kész. A napi foglalási működéshez el kell dönteni, hogy ez Skedda-kiváltási blokkoló-e vagy későbbi kényelmi funkció.
5. **Admin beállítások teljessége:** a fő jogosultság- és helyiségkezelés kész, de a még nem exponált központi paramétereket külön fel kell mérni.

Egy ilyen gap nem automatikusan hiba: az UAT során az üzleti szükséglet alapján `P2`, `P3` vagy `NEM SZÜKSÉGES MOST` döntést kap.

## 15. UAT jegyzőkönyv

Minden manuális futásnál rögzítendő:

- dátum;
- környezet és commit SHA;
- tesztelő;
- teszteset ID;
- státusz;
- rövid megjegyzés;
- hiba esetén GitHub issue száma és P1/P2/P3 besorolása.

## 16. Kilépési feltétel

A rendszer funkcionálisan Skedda-kiváltásra alkalmasnak akkor minősíthető, ha:

1. nincs nyitott P1/P2 üzleti működési hiba;
2. a kritikus AUTH, BOOK, EDIT, CANCEL, REC, ADMIN és MONTH tesztek sikeresek;
3. a napi naptár mobilon, tableten és desktopon használható;
4. a meglévő automatikus tesztek és CI zöldek ugyanazon elfogadott kódon;
5. az UAT során talált scope-döntések dokumentálva vannak.

Ezután következik a production backup/restore automatizálás és a sikeres restore-drill, majd a staging → production bevezetési kapu.
