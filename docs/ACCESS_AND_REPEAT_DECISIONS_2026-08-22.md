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

A támogatott régi kompatibilitási út az auditált `admin_set_user_room_permission(...)` RPC. Az ezen az RPC-n érkező `can_repeat=true` jelzés ugyanabban a tranzakcióban user-szintű repeat jogot kapcsol be. Közvetlen `authenticated` kliens-táblaírás a `user_room_permissions` táblára nincs engedélyezve és nem támogatott.

Explicit user-szintű repeat kikapcsolás a stale legacy `can_repeat=true` értékeket is törli.

A user-szintű repeat módosítás és a legacy room-permission RPC közös, profile-first determinisztikus tranzakciós zársorrendet használ, és külön concurrency regressziós teszt védi. A legacy RPC által kiváltott profil-repeat bekapcsolás is auditált.

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

A `202608220016_user_level_repeat_permission.sql` migráció előtt és után:
- 7 közvetlen user–szoba jogosultsági rekord maradt;
- a közvetlen jogosultságok checksumja változatlan maradt;
- a 2 korábbi legacy repeat user pontosan ugyanaz a 2 user lett user-szintű repeat jogosult;
- egyik normál user sem kapott effektív Tréningterem repeat jogot.

A belső review után a `202608220017_remove_direct_repeat_promotion_trigger.sql` külön kiegészítő migráció a nem támogatott direkt table-trigger utat eltávolítja, és a legacy promóciót kizárólag az auditált, profile-first admin RPC-ben tartja meg.

Rollbackos staging backend-UAT PASS:
- repeat-jogos normál user normál szobában 90 napon belül sorozatot hozhat létre;
- repeat-jog nélküli user sorozata tiltott;
- normál user Tréningterem-sorozata tiltott;
- normál user 90 napot túllépő sorozata tiltott és atomian visszagördül;
- admin 90 napon túl normál szobában sorozatot hozhat létre;
- admin 10 napon túl Tréningterem-sorozatot hozhat létre;
- a rollback után nem maradt próba booking, booking_series vagy audit rekord.

## Nyitott külön kérdés

A meglévő sorozatmotor technikai maximuma jelenleg 400 alkalom / 366 nap. A #65 adminszabály biztosan azt jelenti, hogy az adminra nem vonatkozik a normál user 90/10 napos előrefoglalási limit. A 400/366 technikai korlát teljes eltávolítása külön üzleti/terhelési döntést igényel, ezért ezt a #65 jogosultsági korrekció nem változtatja meg automatikusan.
