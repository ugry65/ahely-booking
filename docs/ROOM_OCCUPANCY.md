# Szobafoglaltság – admin lekérdezés

Döntés: 2026-10-08, projektgazdai kérés. Issue: #285. Első kiadás kizárólag staging;
production kiadás a kipróbálás után külön jóváhagyást igényel.

## Használat

Admin menü → **Szobafoglaltság** (`/admin/szobafoglaltsag`), desktopon és mobilon.

- Dátumtól és dátumig: mindkét szélső nap beleszámít, legfeljebb 366 nap.
- Szobák: több jelölhető; alapból az összes aktív. Inaktív szoba története külön kijelölhető.
- Gyors időszak: ezen a héten / ebben a hónapban / idén; utána **Lekérdezés**.
- Lista: időrend, dátum és hét napja, kezdés–vég, szoba, foglaló, megnevezés, állapot.
  Foglaló szerint szűrhető; a töröltek alapból kimaradnak, kapcsolóval megjeleníthetők.
  100 találat oldalanként; az Excel-export a teljes szűrt listát tartalmazza.
  A meglévő lemondási RPC nem ad megnevezést: töröltnél a cím üres.
- Heti nézet: hétfő–vasárnap, kijelölt szobák egymás alatt, időarányos blokkok,
  sticky időtengely és napfejléc; mobilon a heti rács vízszintesen görgethető.
  Előző/következő hét a kiválasztott dátumtartományon belül. A szűrésen kívüli
  nap szürke, nem jelenik meg szabadként.
- Szabad időpontok: a megjelenített héten, például 14:00–19:00 között legalább
  2 egybefüggő óra, vagy a teljes megadott idősáv. A találat a teljes szabad
  intervallumot mutatja. Összes foglaló számít; törölt foglalás nem foglal helyet.
  Inaktív szoba nem ajánlott. A nyitvatartás az aktuális app_settingsből származik.

Példa: **Idén → csak Tréningterem → Foglalási lista → Lekérdezés**.
A megnevezés az alkalmi ügyfél azonosításához is látható; a foglaló oszlop az
adatbázisban rögzített tulajdonos neve.

## Biztonság és adatelérés

Kizárólag olvasás; nincs foglalás-, pénzügyi-, Auth- vagy auditírás, nincs migráció,
service-role kliens vagy új jogosultsági grant. A page, adatbetöltő és export
külön requireAdmin ellenőrzést használ. A meglévő admin layout is megmarad.

Adatforrás: a sessionhöz kötött Supabase kliens, meglévő
`admin_monthly_active_booking_details` és opcionálisan `admin_cancellation_details`
RPC. Mindkettő DB-oldali `require_active_admin()` védelemmel. Közvetlen bookings
SELECT továbbra is tiltott. Katalógus és névlista a meglévő RLS szerinti read.

A lekérdezések havi bontásban, determinisztikus sorrendben, 500-as kért
oldalmérettel és exact counttal futnak. A ténylegesen visszakapott oldalhosszal
lépünk tovább, ezért alacsonyabb szerver-sorlimit sem hagy ki foglalást.
Legfeljebb 20 000 találat; ennél szűkebb szűrés szükséges. DB-/count-/részleges
betöltési hibánál nincs szabadidő-találat vagy részleges export.
Egy RPC-hívás legfeljebb 20 másodpercet vár.

A több HTTP-kérés nem egyetlen DB-pillanatkép: közben történő foglalásmódosítás
lehetséges. Eltérő count vagy duplikált booking ID esetén újrafuttatást kérünk,
de változatlan darabszámú módosítás nem minden esetben észlelhető. A szabadidő
lista tájékoztató; foglaláskor a meglévő DB-ütközésvédelem dönt.
Időzóna: Europe/Budapest; nap/hónap és DST a meglévő RPC-k szerint.

Excel: valódi XLSX, inline text cellákkal; felhasználói szöveg nem képlet.
Export fejléc: private, no-store. Személyes adat vagy tesztfoglalás nem kerül a repóba.

## Ellenőrzés és átadás

- 31 új automatizált eset: dátumvalidáció és szökőév; DST; szobaszűrő;
  érintkező/átfedő foglalások, töröltek, egybefüggő idő, teljes sáv és nyitvatartás;
  1000 feletti és alacsonyabb szerverlimites lapozás; hiba esetén fail-closed;
  adminhatár, heti ownerfilter figyelmen kívül hagyása; XLSX és exporthiba.
- Teljes Vitest: 246/246 PASS; TypeScript és release-evidence --release PASS.
- Staging DB read-only ellenőrzés: mindkét RPC admin guardja jelen van;
  anonnak nincs active-report EXECUTE, authenticatednek van. Az októberi admin
  aktív riport 104 sort adott. Ezen staging adatok nem a production másolatai.
- PR/CI és deployment bizonyíték az issue/PR átadási bejegyzésében rögzítendő.
- Böngészős ellenőrzéshez staging admin belépés szükséges. Projektgazdai
  elfogadásig a funkció nem production GO.

Regresszió-scope: a régi foglalási naptár, modal, long-press, mobil CSS és
üzleti szabályok nem változnak. A mobil navigáció új linkje ugyanazt a closeMenu
műveletet használja, mint a meglévők. A heti rács saját CSS module-t kapott.

Visszaállítás: az alkalmazásváltoztatás visszavonása stagingen; DB rollback nem kell.
