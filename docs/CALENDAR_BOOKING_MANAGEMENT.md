# A-Hely – naptárból történő foglaláskezelés

Dátum: 2026-08-21

Állapot: **jóváhagyott üzleti/UI baseline**

Ez a dokumentum a napi foglalási naptárból indított szerkesztés, duplikálás és törlés működését rögzíti. Új UI- vagy backend-refaktor ezt külön üzleti döntés nélkül nem ronthatja vissza.

## Műveleti menü

Saját foglalásnál, illetve admin által kezelhető foglalásnál a naptár foglalásblokkjára kattintva/koppintva jelenjen meg:

- **Szerkesztés**
- **Duplikálás**
- **Törlés**

Normál user más felhasználó foglalását nem szerkesztheti és nem törölheti. Admin bármely foglalást kezelhet a meglévő admin jogosultsági szabályok szerint.

## Duplikálás

A duplikálás nem hoz létre azonnal foglalást. A normál foglalási ablak nyílik meg az eredeti foglalás adataival előtöltve:

- helyiség;
- dátum;
- kezdés és befejezés;
- használattípus;
- megjegyzés.

A felhasználó mentés előtt minden adatot módosíthat. A mentés új foglalásként a teljes backend validáción megy át.

## Egyszeri foglalás szerkesztése és törlése

Egyszeri foglalásnál a művelet közvetlenül az adott foglalásra vonatkozik. A meglévő jogosultság-, időrács-, minimumidő-, előrefoglalási-, ütközés- és lemondási szabályok továbbra is érvényesek.

## Ismétlődő sorozat hatóköre

Sorozathoz tartozó alkalom szerkesztése vagy törlése előtt a rendszer kötelezően rákérdez a hatókörre:

1. **Csak ezt az alkalmat** (`occurrence`)
2. **Ezt és az ezt követő alkalmakat** (`following`)
3. **A teljes sorozatot** (`series`)

A `following` hatókör a kiválasztott alkalomtól kezdődő aktív, jövőbeli alkalmakat kezeli.

A `series` hatókör az adott sorozat összes még aktív, jövőbeli alkalmát kezeli. Már lezajlott foglalás történeti adata soha nem írható át vagy törölhető visszamenőleg.

## Sorozatszerkesztés értelmezése

A kiválasztott alkalmon beállított időeltolás, időtartam, helyiség, használattípus és megjegyzés az adott hatókör minden érintett jövőbeli alkalmára következetesen alkalmazódik.

A művelet atomi: ha bármely érintett alkalom jogosultsági, nyitvatartási, előrefoglalási vagy ütközési hibába ütközik, a teljes szerkesztési művelet visszagördül.

Normál user ismétlődő Tréningterem-sorozatot nem kezelhet sorozatként; az admin kivétel változatlanul érvényes.

## Sorozattörlés

Sorozat törlése valójában auditálható lemondás. Fizikai adatvesztés nem történik.

Normál user esetében a lemondási cutoff szabály az összes érintett alkalomra érvényes. Ha a választott hatókör egyik alkalma már a tiltott időablakban van, a teljes sorozatművelet meghiúsul.

Adminra a normál-user lemondási cutoff nem vonatkozik.

## Audit és adatmegőrzés

- A foglalás fizikai törlése továbbra sem megengedett.
- Minden módosított vagy lemondott alkalom külön auditrekordot kap.
- Sorozatszintű művelet külön `booking_scope_operations` rekordban is rögzül.
- A `booking_series_occurrences` tábla az eredeti sorozatgenerálás immutable pillanatképe; a későbbi élő állapot forrása a `bookings`, a változástörténeté az auditnapló.
- A szerveroldali idempotencia a többször elküldött azonos műveletből nem készíthet többszörös módosítást/törlést.

## Regresszióvédelem

Kötelező ellenőrzési esetek:

- egyszeri saját foglalás szerkesztése;
- egyszeri saját foglalás törlése;
- foglalás duplikálása és módosított adatokkal új foglalás létrehozása;
- sorozat: csak egy alkalom szerkesztése;
- sorozat: kiválasztott és következő alkalmak szerkesztése;
- sorozat: teljes jövőbeli sorozat szerkesztése;
- ugyanez a három törlési hatókörrel;
- normál user nem kezelhet más user foglalását;
- admin kezelhet más user foglalását;
- normál user cutoff-on belüli sorozattörlése elutasított;
- ütköző sorozatszerkesztés atomi módon elutasított;
- naptár mobil long-press, scroll, sticky órasáv és 7 napos felső dátumsáv nem regresszálhat.

Kapcsolódó dokumentumok: `docs/BOOKING_UI_UX_BASELINE.md`, `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`, `docs/RECURRING_BOOKING_RULES.md`.
