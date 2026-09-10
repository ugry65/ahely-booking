# Tréningterem csoportos díjazás – üzleti döntés

Dátum: 2026-08-25
Kapcsolódó issue: #82

## Végleges üzleti szabály

A Tréningterem **csoportos használatának alapértelmezett díja 5 000 Ft/óra**.

A díj azonban foglalásonként eltérhet. Adminisztrátor Tréningterem csoportos foglalás létrehozásakor az alapértelmezett 5 000 Ft/óra értéket felülírhatja, például magasabb létszám vagy egyedi megállapodás miatt.

Ismétlődő, admin által létrehozott Tréningterem csoportos sorozatnál az admin által megadott óradíj a sorozat létrehozott aktív alkalmaira kerül rögzítésre.

## Történeti adatmegőrzés

A ténylegesen alkalmazott csoportos óradíjat **magán a foglaláson kell rögzíteni**. A későbbi alapdíj-változás nem írhatja át a korábbi foglalások árát.

Ezért a havi elszámolás nem az aktuális globális alapdíjból számolja vissza a múltat, hanem az adott foglaláson tárolt óradíjat használja.

A már lezárt havi settlement snapshot ezen felül foglalási soronként is megőrzi az alkalmazott óradíjat és összeget.

## Jogosultság és audit

- Normál user a csoportos óradíjat nem módosíthatja.
- Admin módosíthatja a Tréningterem csoportos foglalás díját.
- Az admin díjfelülírás auditnapló-bejegyzést hoz létre: ki, mikor, mely foglalásnál/sorozatnál milyen értéket állított be.
- Negatív díj nem adható meg.

## Díjszámítási prioritás

1. **Free user:** minden foglalás díja 0 Ft, a Tréningterem csoportos foglalásé is.
2. Nem-Free user Tréningterem csoportos használata: a foglaláson rögzített csoportos óradíj érvényes.
3. Ha a foglaláson még nincs történetileg rögzített érték, migrációkor/defaultként 5 000 Ft/óra kerül rá.
4. A Tréningterem egyéni használata továbbra is a user normál havi díjazási szabálya szerint számolódik.

## UI

Admin foglalási felületen, ha:
- helyiség = Tréningterem;
- használat = Csoportos;

akkor megjelenik a **Csoportos óradíj** mező, alapértelmezett értéke 5 000 Ft/óra. Az admin ezt a foglalás vagy sorozat mentése előtt felülírhatja.

Normál user számára ez az ármező nem szerkeszthető és nem szükséges a foglalási folyamatban megjeleníteni.

## Adatbiztonsági elv

Foglalás nem maradhat ár nélkül: Tréningterem csoportos használatnál a backend adatbázis-trigger 5 000 Ft/óra defaultot rögzít akkor is, ha az admin külön felülírása technikai okból nem futna le. Így az elszámolás fail-safe állapotban marad, és a hiba nem eredményez 0 Ft-os vagy ismeretlen díjú foglalást.
