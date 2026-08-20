# Mobil naptár érintéses működés

A mobil napi naptár alapértelmezett gesztusa a görgetés.

- Függőleges húzás a naptár teljes felületén görgeti az oldalt.
- Vízszintes húzás a helyiségek között mozgatja a naptárat.
- A bal oldali órasáv vízszintes görgetéskor rögzített marad.
- Foglaláskijelölés érintőképernyőn csak kb. 500 ms hosszú nyomás után aktiválódik.
- Ha a felhasználó a long press aktiválódása előtt érdemben megmozdítja az ujját, a foglaláskijelölés megszakad és a gesztus görgetés marad.
- Asztali egérrel a meglévő közvetlen húzásos kijelölés megmarad.

A gesztuskezelés kizárólag UI-réteg; a foglalás végleges jogosultság-, időrács-, limit- és ütközésellenőrzése továbbra is backend oldalon történik.
