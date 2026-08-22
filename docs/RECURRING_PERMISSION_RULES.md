# Ismétlődő foglalási jogosultság – üzleti és technikai szabály

Állapot: elfogadott üzleti szabály, 2026-08-21; technikai pontosítás 2026-08-22.
Kapcsolódó issue-k: #44, #65. A korábbi #43 szabályt a #44/#65 felülírja.

## Üzleti modell

Az ismétlődő foglalási jogosultság **felhasználó-szintű**, nem helyiség-szintű.

Normál felhasználónál:
- ha a user ismétlődő foglalási joga KI, egyetlen normál helyiségben sem hozhat létre sorozatot;
- ha a user ismétlődő foglalási joga BE, minden olyan **normál** helyiségben hozhat létre sorozatot, amelyre aktuálisan foglalási (`can_book`) joga van;
- a foglalási jog származhat helyiségcsoportból vagy közvetlen user–szoba kivételből;
- a Tréningterem kivétel: normál user ott user-szintű repeat joggal sem hozhat létre ismétlődő foglalást.

Adminisztrátornál:
- az ismétlődési jogosultsági korlát nem alkalmazandó;
- Tréningteremben is létrehozhat ismétlődő foglalást.

## Adatmodell

A kanonikus jogosultság:

`profiles.can_repeat_bookings boolean`

Az effektív repeat jogosultság normál usernél:

`profil repeat joga BE` + `effektív can_book a helyiségre` + `a helyiség nem Tréningterem`.

A `user_room_permissions.can_repeat` mező történeti/kompatibilitási okból átmenetileg megmarad, de **nem ez az effektív repeat-jog forrása**.

## Migráció és kompatibilitás

Adatvesztés/jogvesztés nem megengedett.

Ezért:
- ha a migráció időpontjában egy usernek bármely közvetlen user–szoba rekordján `can_repeat=true` van, a profil-szintű `can_repeat_bookings` értéke BE állapotból indul;
- a támogatott legacy kompatibilitási út az auditált `admin_set_user_room_permission(...)` RPC: az ott érkező `can_repeat=true` jelzés a user-szintű repeat jogot is bekapcsolja;
- közvetlen authenticated kliens-táblaírás a `user_room_permissions` táblára nem támogatott és nincs engedélyezve;
- a legacy per-room flag önmagában nem szűkíti le az ismétlődési jogot arra az egy helyiségre;
- a user-szintű repeat jog admin általi kikapcsolásakor a régi `can_repeat=true` jelzők törlődnek, hogy elavult adat ne tudja később visszakapcsolni a jogot;
- a profil-repeat RPC és a legacy room-permission RPC ugyanazt a profile-first zársorrendet használja.

## Admin felület

Az ismétlődő foglalási jog a `Felhasználók` oldalon, a kiválasztott user tulajdonságaként kezelendő.

A közvetlen user–szoba jogosultsági felületen helyiségenkénti `Ismételhet` kapcsoló nem jelenhet meg.

## Audit és backend-védelem

A user-szintű repeat jog módosítása:
- csak aktív admin által végezhető;
- backend RPC-n keresztül történik;
- auditnapló-bejegyzést készít before/after állapottal és correlation ID-val;
- a legacy RPC által kiváltott profil-repeat bekapcsolás is auditált;
- normál user közvetlen RPC-hívással sem módosíthatja saját vagy más user repeat jogát.

## Előrefoglalási limitek

A repeat jogosultság és az előrefoglalási limit két külön szabály.

Elfogadott limitek:
- normál helyiségek: alapértelmezés 90 nap, admin által konfigurálható;
- Tréningterem normál egyszeri foglalás: alapértelmezés 10 nap, admin által konfigurálható;
- adminra a normál user limitjei nem vonatkoznak.

A user-szintű repeat jog bekapcsolása **nem** jelent felmentést az előrefoglalási limit alól.

## Kötelező regressziós esetek

- repeat jog KI → nincs ismételhető normál helyiség;
- repeat jog BE + több foglalható normál helyiség → mind ismételhető;
- csoportból kapott `can_book` ugyanúgy részt vesz az effektív jogosultságban;
- közvetlen plusz `can_book` ugyanúgy részt vesz;
- Tréningterem normál usernek továbbra is tiltott;
- admin Tréningteremben is ismételhet;
- normál user közvetlen admin RPC-hívása tiltott;
- repeat jogosultság változása auditált;
- legacy `can_repeat=true` migrációkor nem okozhat jogosultságvesztést;
- legacy RPC `can_repeat=true` a profil-repeat jogot auditáltan bekapcsolja;
- repeat jog kikapcsolásakor nem maradhat effektív ismétlődési jog;
- konkurens repeat OFF és legacy TRUE RPC közös zársorrendben, deadlock nélkül sorosodik.
