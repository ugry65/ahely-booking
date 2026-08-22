# PR #76 – független jogosultsági review brief

Állapot: kötelező merge előtti független review.
Kapcsolódó issue: #75.
PR: #76 – `feature/room-groups-user-admin-75` → `main`.

## Review célja

Függetlenül ellenőrizni, hogy a helyiségcsoportok, user-szintű kivételek, Admin/User szerepkör-kezelés és stabil naptárszínek bevezetése nem nyit jogosultsági rést, nem veszít el korábbi jogosultságot, és nem sérti a naptári adatvédelmi szabályokat.

## Kötelező üzleti szabályok

1. A kanonikus helyiségcsoportok:
   - `A-Hely`: Gyerek szoba, Pitypang szoba, Csoport szoba;
   - `Másik Hely`: 1.Szoba-családi, 2.Szoba, 3.Szoba, 4.Szoba, 5.Szoba, 6.Szoba;
   - `Tréningterem`: Tréningterem;
   - `Forrás tér`: Forrás tér.
2. Egy user több csoport tagja lehet.
3. Effektív foglalási jog = közvetlen user–szoba jog + aktív csoportokból örökölt `can_book`.
4. `can_repeat` kizárólag közvetlen user–szoba jogosultságból származhat. Csoportból soha.
5. A meglévő közvetlen jogosultságokat a csoportmodell nem törölheti és nem írhatja felül.
6. Szerepkör-váltás csak admin által, backend oldali ellenőrzéssel, auditáltan történhet.
7. Az utolsó aktív adminisztrátort nem lehet lefokozni vagy deaktiválni, konkurens adminműveletek esetén sem.
8. Minden user stabil, profilhoz kötött naptárszínt kap; az első 40 user számára 40 külön palettaszín áll rendelkezésre.
9. Ha más foglalók neve rejtett, más user stabil színe sem kerülhet ki a backendből. Admin és a foglalás tulajdonosa a megfelelő színt továbbra is láthatja.
10. A foglalási motor, ütközésvédelem, 30 perces rács, minimum idő, mobil naptár és ismétlődő foglalások korábbi működése nem regresszálhat.

## Kiemelten átnézendő fájlok

- `supabase/migrations/202608220013_room_group_business_model.sql`
- `supabase/migrations/202608220014_admin_user_role_guard.sql`
- `supabase/migrations/202608220015_stable_user_calendar_colors.sql`
- `src/app/(protected)/admin/felhasznalok/actions.ts`
- `src/app/(protected)/admin/felhasznalok/page.tsx`
- `src/app/(protected)/admin/helyisegek/actions.ts`
- `src/app/(protected)/admin/helyisegek/page.tsx`
- `src/app/(protected)/foglalasok/calendar-booking-grid.tsx`
- `supabase/tests/database/026_room_group_business_model.sql`
- `supabase/tests/database/027_admin_user_role_guard.sql`
- `supabase/tests/database/028_stable_user_calendar_colors.sql`
- továbbá minden PR #76 által módosított régi jogosultsági/recurring teszt.

## Kérdések a reviewerhez

- Van-e privilege escalation út normál userből admin vagy más user jogosultságainak módosítására?
- A `SECURITY DEFINER` admin RPC-k minden hívási úton ténylegesen aktív admint követelnek-e?
- Az advisory lock megfelelően megakadályozza-e, hogy két egyidejű művelet az utolsó aktív admint megszüntesse?
- A csoporttagság deaktiválása/módosítása determinisztikusan és azonnal változtatja-e az effektív `can_book` jogot?
- Biztosan lehetetlen-e `can_repeat` jogot csoportból örökölni vagy csoport-RPC-n keresztül létrehozni?
- A közvetlen user–szoba kivételek és repeat jogok minden migráció után megmaradnak-e?
- Van-e olyan naptári API/read-model út, amely név rejtése mellett mégis stabil színt, címet vagy más azonosító adatot szivárogtat?
- A 40 szín kiosztása konkurens user-létrehozás mellett stabil és érvényes marad-e?
- Az admin UI kizárólag auditált backend RPC-ken keresztül módosít-e jogosultsági adatot?
- Hiányzik-e olyan negatív vagy konkurens regressziós teszt, amely a fenti szabályokhoz kritikus?

## Már lefuttatott kontrollok

- Teljes Application checks: unit test + typecheck + production build.
- Teljes Database tests: pgTAP, párhuzamos foglalás, párhuzamos módosítás, room-access admin concurrency, recurring concurrency, schema lint.
- Staging migráció előtti/utáni jogosultsági checksum kontroll.
- Stagingen a profil-, aktív admin-, group membership-, direct permission- és direct repeat darabszámok megőrzésének ellenőrzése.
- Stagingen a kanonikus csoportok 3/6/1/1 szobás összetételének és 0 group-repeat jogának ellenőrzése.
- Anon admin-RPC execute tiltás célzott ellenőrzése.

## Elvárt review kimenet

A reviewer sorolja a megállapításokat súlyosság szerint (`critical`, `high`, `medium`, `low`) fájl- és lehetőleg sorszintű hivatkozással. Külön jelezze, ha nincs blokkoló megállapítás. Critical/high hiba esetén a PR nem mehet UAT-elfogadás/merge irányába javítás és új teljes regressziós futás nélkül.
