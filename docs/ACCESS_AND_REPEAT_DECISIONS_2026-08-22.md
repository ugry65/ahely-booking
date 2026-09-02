# Jogosultsági és ismétlődési döntések – 2026-08-22

Ez a dokumentum a 2026-08-22-én érvényes, kanonikus jogosultsági modellt rögzíti. Ha korábbi issue vagy dokumentum ezzel ellentétes, ez a frissebb üzleti döntés az irányadó.

## Helyiségcsoportok – #75

A korábbi, helyiségcsoportokat elvető #72 döntés felülírva.

Kanonikus csoportok:
- `A-Hely`: Gyerek szoba, Pitypang szoba, Csoport szoba
- `Másik Hely`: 1.Szoba-családi, 2.Szoba, 3.Szoba, 4.Szoba, 5.Szoba, 6.Szoba
- `Tréningterem`: Tréningterem
- `Forrás tér`: Forrás tér

Egy user több csoporthoz is tartozhat. Az effektív `can_book` jogosultság az aktív csoporttagságokból és az opcionális közvetlen user–szoba kivételjogok uniójaként számítandó. A csoportjogokat nem másoljuk szét userenként, mert az jogosultsági driftet okozna.

A helyiségcsoport kizárólag foglalási (`can_book`) jogot ad. Ismétlődő foglalási jogot csoport nem adhat.

A meglévő közvetlen user–szoba jogosultságok megőrzendők, és kompatibilitási/kivételjogként továbbra is részei az effektív jogosultságnak.

## Ismétlődő foglalási jogosultság – #65

Az ismétlődő foglalási jogosultság user-szintű üzleti jogosultság, nem helyiségenkénti jog.

Normál user:
- ha `can_repeat_bookings = true`, minden olyan aktív normál helyiségben hozhat létre ismétlődő foglalást, amelyre effektív `can_book` joga van;
- ha `can_repeat_bookings = false`, ismétlődő foglalást nem hozhat létre;
- Tréningteremben ismétlődő foglalást akkor sem hozhat létre, ha a user-szintű repeat joga be van kapcsolva;
- normál helyiségnél az aktuális központi/user override előrefoglalási limit érvényes (jelenlegi default 90 nap);
- Tréningteremnél a külön training limit érvényes (jelenlegi default 10 nap).

Admin:
- nem kötött a normál user repeat-jogához;
- bármely aktív helyiségben hozhat létre ismétlődő foglalást;
- a normál user 90 napos és Tréningterem 10 napos előrefoglalási limitjét backend-oldalon bypassolja.

## Legacy kompatibilitás

A régi `user_room_permissions.can_repeat` mező adatvesztés elkerülése miatt megmarad kompatibilitási jelzőként, de nem önálló room-szintű jogosultsági forrás.

Migrációkor bármely korábbi `can_repeat=true` közvetlen jog a user `can_repeat_bookings=true` profiljogát kapcsolja be, így meglévő repeat jogosultság nem vész el.

A támogatott legacy kompatibilitási út az auditált `admin_set_user_room_permission(...)` RPC. Az ezen keresztül érkező `can_repeat=true` a user-szintű repeat jogot bekapcsolja. Közvetlen kliensoldali `user_room_permissions` táblaírás nem támogatott. Explicit user-szintű repeat kikapcsolás a stale legacy `can_repeat=true` értékeket is törli.

A user-szintű repeat módosítás és a legacy room-permission RPC közös, determinisztikus, profile-first tranzakciós zársorrendet használ, és külön concurrency regressziós teszt védi.

## Adat- és jogosultságbiztonsági kapuk

A #65 változtatásnál kötelező:
- meglévő közvetlen jogosultságok előtte/utána összevetése;
- legacy repeat userek megőrzése;
- backend-oldali jogosultságellenőrzés;
- auditált admin repeat-jog módosítás;
- pgTAP regressziós tesztek;
- konkurens repeat-jog módosítás tesztje;
- staging UAT;
- kritikus jogosultsági változás miatt független review merge előtt.

## Staging ellenőrzés – 2026-08-22

A `202608220016_user_level_repeat_permission.sql` migráció után:
- 7 közvetlen user–szoba jogosultsági rekord maradt;
- a közvetlen jogosultságok checksumja változatlan maradt;
- a 2 korábbi legacy repeat user pontosan ugyanaz a 2 user lett user-szintű repeat jogosult;
- egyik normál user sem kapott effektív Tréningterem repeat jogot.

A `202608220017_remove_direct_repeat_promotion_trigger.sql` staging alkalmazása előtt és után:
- profiles: 5 → 5;
- direct user-room permissions: 7 → 7;
- legacy `can_repeat=true`: 2 → 2;
- profile-level repeat enabled: 2 → 2;
- group memberships: 2 → 2;
- direct permission checksum változatlan: `d0d2eab502eeb2b09827bd0eb08b8372`;
- nem támogatott promotion trigger: 1 → 0;
- külön `service_role` EXECUTE grant az admin repeat RPC-n: true → false.

Rollbackos staging backend-UAT PASS:
- repeat-jogos normál user normál szobában 90 napon belül sorozatot hozhat létre;
- repeat-jog nélküli user sorozata tiltott;
- normál user Tréningterem-sorozata tiltott;
- normál user 90 napot túllépő sorozata tiltott és atomian visszagördül;
- admin 90 napon túl normál szobában sorozatot hozhat létre;
- admin 10 napon túl Tréningterem-sorozatot hozhat létre;
- a `017` után a támogatott legacy admin RPC `can_repeat=true` továbbra is user-szintű repeat jogot kapcsol be és két auditrekordot ír (profil-promóció + room permission);
- rollback után nem maradt próba booking, booking_series, permission, profil vagy audit rekord.

## Független review – PR #77

A független Claude security/authorization/concurrency review eredménye: **APPROVE**.

- CRITICAL: nincs
- HIGH: nincs
- MEDIUM: nincs
- LOW: 2 megfigyelés, mindkettő merge előtt lezárva

Lezárások:
1. külön direct-only `can_book` → user-szintű repeat regressziós teszt bekerült;
2. a felesleges `service_role` EXECUTE grant lekerült az admin repeat RPC-ről, és ezt külön regressziós teszt védi.

A review-fixek utáni teljes validáció a `309c37555872dc93c84a4060ac9b581c6f04531b` kód/test headen:
- Application checks #257 PASS;
- Database tests #231 PASS;
- 31 pgTAP fájl / 420 teszt PASS;
- booking, mutation, room-access, recurring, last-admin, calendar-color és repeat-permission concurrency PASS;
- DB lint PASS.

## Sorozathossz technikai biztonsági plafon – végleges döntés

A meglévő sorozatmotor technikai maximuma **megmarad**:
- legfeljebb **400 alkalom egy ismétlődő sorozatban**;
- legfeljebb **366 nap** az első alkalomtól számítva.

Ez a 400-as érték **nem userenkénti vagy éves összes foglalási limit**, hanem egyetlen sorozat technikai maximuma. Több külön sorozat ettől függetlenül létrehozható, ezért nagy havi foglalási volumen önmagában nem jelent korlátot.

Az admin továbbra is bypassolja a normál user 90 napos és Tréningterem 10 napos előrefoglalási limitjét, de a 400 alkalom / 366 nap globális sorozatbiztonsági plafon rá is érvényes.

Üzleti döntés: **a plafon most marad**. Ha később tényleges működési korlátként jelentkezik, külön terhelésvizsgálat és regressziós ellenőrzés után emeljük; nem távolítjuk el előre indokolatlanul.

## PR #77 lezárási kapuk

A technikai implementáció, teljes CI, staging migráció, adatmegőrzési ellenőrzés és független review lezárt. A sorozathossz üzleti döntése is lezárt: 400 alkalom / 366 nap marad.

Történeti státusz helyesbítése (2026-08-30): a [PR #77 végső UI UAT szakasza](https://github.com/ugry65/ahely-booking/pull/77) szerint az oszlop-SELECT grant javítása után a projektgazda 2026-08-22-én elfogadta a böngészős UAT-t: **PASS**. A korábbi „végső UI/UAT még szükséges” megjegyzés tehát elavult, nem új tesztfeladat.

Ez a helyesbítés a korábbi elfogadást vezeti át; nem ad új merge-engedélyt egy jelenlegi branchre vagy productionre.

A PR merge-je automatikusan nem engedélyezett pusztán az UAT elfogadásával.
