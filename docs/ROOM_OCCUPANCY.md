# Szobafoglaltság – admin lekérdezés

Döntés és élesítés: 2026-10-08, projektgazdai kérés és külön élesítési jóváhagyás.
Állapot: **elfogadott, productionben elérhető**.
[Issue #285](https://github.com/ugry65/ahely-booking/issues/285) lezárva;
[fejlesztési PR #286](https://github.com/ugry65/ahely-booking/pull/286) mainbe,
[release PR #287](https://github.com/ugry65/ahely-booking/pull/287) productionbe merge-elve.

Éles elérés: https://foglalas.a-hely.com/admin/szobafoglaltsag (admin belépéssel).
A funkció dátum- és szobaszűrt foglalási listát, heti foglaltságot,
szabadidő-keresést és Excel-exportot ad, üzleti adatok módosítása nélkül.

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
- PR #286 és main application-checks / evidence-consistency SUCCESS; Next.js build PASS.
- A release #287 három kötelező kapuja SUCCESS: Production release gate,
  application-checks, evidence-consistency.
- Projektgazdai elfogadás: 2026-10-08 18:36 Europe/Budapest,
  „jó lesz. élesíthető”. Ez felhasználói elfogadás, nem új tételes UAT-napló.
- Saját, bejelentkezett staging UI-UAT nem igazolt (biztonságos belépési kérés
  időtúllépése); bejelentkezett production UI-UAT nem történt. Ezeket nem
  jelöljük automatizált vagy saját böngészős PASS-nak.

## Bevezetési bizonyíték – 2026-10-08

| Környezet | Git-verzió | Vercel deployment | Ellenőrzés |
| --- | --- | --- | --- |
| Staging, main | `1f74f2f6cf0afca6531cd4706a0564892f7c5b8d` | `dpl_Bq8R8j3NkRBuHT6x6Yj83fdLGAmZ` | READY, egyező SHA; health HTTP 200; admin oldal belépésre irányít |
| Production, production ág | `a29e5ae0134bc39b7999b0dd9ac912f30a872bde` | `dpl_6yvQXemtjAQAy2CJQRvd6EUoAyxD` | READY, egyező SHA; foglalas.a-hely.com alias; health HTTP 200, ok=true, database=ok |

Productionben az oldal és az export bejelentkezés nélkül HTTP 307 → /belepes.
A staging normál felhasználó admin RPC-hívása insufficient_privilege hibával
elutasítva. A bevezetés nem igényelt migrációt, grantot, Auth-, secret- vagy
environment-módosítást; üzleti adatírás nem történt.

Források:
[staging átadás](https://github.com/ugry65/ahely-booking/issues/285#issuecomment-6064483182),
[projektgazdai jóváhagyás](https://github.com/ugry65/ahely-booking/issues/285#issuecomment-6064549536),
[production átadás](https://github.com/ugry65/ahely-booking/issues/285#issuecomment-6064607708).

A release a teljes akkori main kiadása volt: a szobafoglaltság mellett a korábban
kért pénzügyi export Állapot/Revision oszlopeltávolítása és a staging-only aktivitás-
ellenőrzés fájljai is bekerültek. A staging aktivitás élő jobja csak mainen fut;
a Supabase hétnapos megfigyelése külön #282 feladat, nem e funkció nyitott hibája.

## Későbbi ellenőrzés

Admin belépés után: Idén → csak Tréningterem → Foglalási lista → Lekérdezés,
majd azonos szűrés Excel-exportja. Heti nézetben több kijelölt szobával
14:00–19:00 / legalább 120 perc, majd teljes sáv ellenőrzése.
Hasonlítsd a találatokat a meglévő foglalási naptárhoz; a próbához nem szükséges
tesztfoglalást létrehozni. A projektgazdai elfogadás lezárt; ez célzott későbbi
regressziós útmutató, nem kötelező új elfogadási kör.

Regresszió-scope: a régi foglalási naptár, modal, long-press, mobil CSS és
üzleti szabályok nem változnak. A mobil navigáció új linkje ugyanazt a closeMenu
műveletet használja, mint a meglévők. A heti rács saját CSS module-t kapott.

Visszaállítás: hibánál külön jóváhagyott alkalmazás-rollback vagy javító PR;
DB rollback nem kell. A kiadás előtti ismert jó production deployment:
`dpl_9jZoE95DS9tzq3ZbEMSiF5Z2syWL`, commit
`c0c7158f86946fffc1801eec348e27aa908cf56a`.
Teljes deployment-rollback más, vele együtt kiadott változásokat is visszavonhat;
ezért előbb a hibát és a rollback scope-ját ellenőrizni kell.
