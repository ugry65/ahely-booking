# Szobánkénti havi és listanézet – #289

Döntés: 2026-10-13, projektgazda: „Keszitsd el a staging rendszeren és jóváhagyás után aktivaljuk”.
Állapot: fejlesztési ág / staging átadás előkészítése. Production engedély nincs.
Baseline main: `b311ca66187589c6b72986d2ef57e529078dcb13` (#288).
Ág: `feature/room-month-list`.

## Használat

Foglalási naptár → **Napi / Havi / Lista**. Normál felhasználók és adminok is használhatják.

- Havi: egy jogosult szoba, választható hónap vagy előző/következő hónap. Hétfő–vasárnap, minden tényleges naptári nap; a hónapon kívüli napok nem mutatnak szabad időt.
- Napi foglaltsági sáv: aktuális nyitvatartás, zöld szabad / sötét foglalt; szöveges foglalásszám és megfelelő szabad intervallum is látható. A szín nem az egyetlen információhordozó.
- A havi naptárban egy napra kattintva közvetlenül az adott nap foglalási naptára nyílik meg (2026-10-13-i projektgazdai pontosítás). A dátum és a kiválasztott szoba a napi nézet URL-jében megmarad. A havi oldal kezdeti napösszefoglalója külön továbbra is látható. A foglalási cím csak a meglévő naptár RPC által engedélyezett körben látszik.
- Lista: Foglalások vagy Szabad időpontok. Dátumtartomány maximum 366 nap; opcionális hét napja, idősáv, legalább 1 órás időtartam félórás lépésekben.
- A keresési idősáv/időtartam csak a szabad időkre vonatkozik; a foglalások listája és a napi foglaltsági sáv minden aktív foglalást mutat. A hét napja mindkét listát szűri.
- Az üres napok teljes szabad sávként megjelennek. Különálló rövid időablakokat nem adunk össze egybefüggő időként.
- Lista 100 találat oldalanként; az összes foglalási adat betöltése és a szabadidő-számítás teljes eredményen történik.
- Foglalás: a találat elejétől a keresett időtartamot előtöltjük a meglévő napi gyorsfoglalási ablakba. A dátum/szoba/kezdés/vég módosítható; nincs automatikus mentés. A mai napnál csak a jelenlegi idő utáni következő félórás kezdés ajánlható.
- Előrefoglalási határon túli szabad idő megtekinthető, de nincs Foglalás gomb. Normál user egyedi limitje és a Tréningterem alacsonyabb limitje érvényes; adminnál nincs ilyen előrefoglalási korlát. A végső ellenőrzés továbbra is a backend feladata.
- Frissítés link teljes új GET-kérést indít. Több lekérdezés közben a foglaltság változhat; a lista tájékoztató, a mentéskor az adatbázis ütközésvédelme dönt.

## Technikai és biztonsági modell

- A meglévő `/foglalasok` útvonal `view=month|list` ága, külön server component és CSS module.
- `requireActiveProfile` + sessionhöz kötött Supabase kliens.
- Szobakatalógus: meglévő `list_bookable_rooms`. Ismeretlen/jogosulatlan room UUID hibát ad, még a foglaltsági adatlekérés előtt.
- Adatforrás: kizárólag meglévő privacy-aware `list_calendar_bookings`; nincs normál user számára megnyitott admin riport, direkt bookings SELECT, service role vagy új EXECUTE grant.
- Kérésenként maximum 31 nap; Europe/Budapest helyi éjfélből UTC határok, ezért a DST-nap is helyes. Exact count, stabil start_at/booking_id sorrend, 500-as kért lapok és a tényleges oldalhossz szerinti továbblépés. Összesen maximum 20 000 foglalás, RPC-nként 20s timeout.
- Hiba, hiányzó count/beállítás, duplikált ID vagy érvénytelen időadat esetén nincs naptár/szabadidő-eredmény. A több RPC nem egyetlen DB-pillanatkép; azonos darabszámú párhuzamos módosítás nem minden esetben észlelhető.
- Saját profilból csak az advance_booking_days_override szükséges; a többi foglaló profilját nem olvassuk. Név/cím maszkolását a meglévő DB RPC végzi.
- Nincs schema-, jogosultság-, pénzügyi-, foglalási write-, e-mail-, secret- vagy workflow-módosítás.
- Napi naptár rács/CSS/long-press/sticky/kezelési menü változatlan; a nézetváltó új elem. A gyorsfoglalási modal opcionális, validált előtöltést kap; a normál `+` működése megmarad.
- A történeti release-evidence nyilvántartásban rögzített fájlok nem változnak; ezt az új UI scope-ot jelen dokumentum és #289 rögzíti.

## Ellenőrzési terv és bevezetési korlát

Automatikus: hónaphossz/szökőév, közvetlen hónapválasztás, érvénytelen szűrők, DST-határok, üres nap, érintkező/átfedő blokkok, különálló rövid rések, nyitvatartás, hét napja, előrefoglalási határ és egyedi/Tréningterem limit, mai jövőbeli félóra, modal előtöltés, jogosulatlan room, session guard, sorlimites lapozás, későbbi kérés hibája és fail-closed UI, havi/lista render.

Staging read-only SQL: a két naptár RPC return típusa egyezik az alkalmazással; authenticated EXECUTE=true, anon=false. Az opening_time/closing_time string, az advance limitek JSON number típusúak. Normál user szerepkörben az engedélyezett katalógus, saját profil és a négy beállítás olvasható. A lekérdezés nem hozott létre tesztfoglalást.

Staging projekt: `ahely-booking-staging-web`, `prj_LzVgZgZBCAj4zA64YoYED3XkLGKW`, team `team_zUlC4KlLvkMuz1zRdq8ssAk2`; ellenőrzött Supabase cél: `fvwapntzhavhgazeflri`. A Vercel `production` target ezen külön staging projekt stabil URL-jét jelenti, nem az A-Hely éles projektjét.

Kézi kipróbálás: belépés stagingre → Havi → szoba/hónap → nap részletei; Lista → Szabad időpontok → 14:00–20:00 / 2 óra / kedd; Foglalás → előtöltés ellenőrzése, Mégse; mobil napi görgetés/long-press/+; Tréningterem határon túli szabad napnál nincs foglalásgomb. Élesítés kizárólag a projektgazda későbbi elfogadása után, a meglévő production release kapukkal.

Visszaállítás: a korábbi staging deployment ismét használható; DB-rollback nem szükséges. Production branch és éles deployment e feladatban változatlan.

## Fejlesztési ellenőrzés – 2026-10-13

- Teljes Vitest: 282/282 PASS, 36 új eset a 246 tesztes baseline-hoz képest.
- TypeScript és Next.js build PASS; `check-release-evidence.mjs --release` PASS; `git diff --check` PASS.
- Célzott React/read-only adatút review: session guard, room UUID ellenőrzés, meglévő RPC privacy, teljes lapozás, hiányos adatok kizárása, dátum/DST, félórás modal preset és napi UX baseline ellenőrizve. Ez saját kódellenőrzés, nem független pénzügyi/jogosultsági write-review; ilyen write-változtatás nincs a scope-ban.
- Server component havi/lista/hibás adat/üres jogosultsági katalógus render tesztek PASS, szintetikus adatokkal. Ez nem valódi, bejelentkezett mobil böngészős UAT.
- A staging webhely megnyitása a belépési oldalt mutatta; aktív staging munkamenet nélkül a bejelentkezett UI-UAT nem igazolt. A helyi render-fixture cloud böngészőből nem érhető el. A kézi projektgazdai kipróbálás és elfogadás ezért külön lépés marad.
- Staging környezeti cél `NEXT_PUBLIC_SUPABASE_URL=https://fvwapntzhavhgazeflri.supabase.co` élő read-only ellenőrzéssel igazolva. Secret érték nem került dokumentumba/repóba.

## Staging kiadási útvonal egyeztetése

A `src/lib/vercel-deployment-identity.ts` őre a stabil staging projektben kizárólag `main` refet fogad el. A feature-ág preview buildje READY (`dpl_DjsBzFjvDZfYtyUQN9PdtpVz4KUd`, SHA `d523e0df043f00e6b80e584ed1c2fd255b788d66`); a közvetlen feature → staging production-target kérés (`dpl_AxMMZFfjUwZ3VCqS2xt2B3eoiazg`) ezért helyesen ERROR lett. A korábbi stabil staging egészséges maradt (health 200, database=ok).

A védelmet nem módosítjuk és preview alias-promócióval sem kerüljük meg. A #290 PR CI-kapui (application-checks/evidence-consistency) és kódellenőrzése után a változtatás mainbe kerül, ami kizárólag a külön staging stabil alkalmazását frissíti. Ezt a staging megvalósítási engedély szükséges részeként kezeljük. A production branch külön és változatlan; a felhasználói kipróbálás után külön production release PR és jóváhagyás szükséges.

## Laptopos megjelenési javítás – 2026-10-13, projektgazdai staging visszajelzés

A projektgazda laptopos képernyőképe alapján a havi és listanézet tartalma 480px széles kártyákba szorult, nagy üres helyet hagyva a képernyőn. Ez nem a mobil breakpoint bekapcsolása volt: az új kártyák örökölték az általános `.card { width: min(100%, 30rem) }` szabályt. Az új oldal 1200px-es max-width és margin:auto beállítása a meglévő desktop széles oldalelrendezéssel is ütközött.

Javítás: a szűrő, havi naptár, napi részletek és listák a már meglévő `wide-card` osztályt kapják. A külön `.page` max-width/margin szabálya megszűnik; a széles desktop és mobil külső elrendezést a meglévő, regresszióvédett közös CSS biztosítja. Globális CSS, napi naptár, adatbetöltés, jogosultság és üzleti logika nem változik.

Új offline böngészős regressziós ellenőrzés: `scripts/check-room-calendar-layout.mjs`. A valódi server component szintetikus adatokkal renderelt HTML-jét és a tényleges global/mobile/calendar/module CSS-t méri, főmenüvel. Havi, szabadidő-lista és foglalási lista; 1920/1366/1024/768/390/320px; teljes szélesség, képernyőhatárok és vízszintes túllógás ellenőrzése. 18/18 PASS. 1366px-nél a kártyák 1322px, 1920px-nél 1876px, 390px-nél 358px szélesek. A régi CSS/markup visszaállításával ugyanez az ellenőrzés a 480px-es szélesség miatt FAIL lett, tehát a teszt ténylegesen érzékeli az eredeti hibát. Ez offline browser-layout teszt, nem bejelentkezett élő staging UAT.

Futtatás (telepített Playwright/Chromium szükséges; nincs új alkalmazásfüggőség):

```sh
ROOM_CALENDAR_PREVIEW=/tmp/room-calendar-layout pnpm test
# Alapesetben a telepített playwright csomagot/böngészőt használja.
# Más telepítésnél ROOM_LAYOUT_PLAYWRIGHT_MODULE és ROOM_LAYOUT_BROWSER adható meg.
node scripts/check-room-calendar-layout.mjs /tmp/room-calendar-layout
```

Teljes Vitest 282/282, typecheck PASS. A #291 production PR draft és szüneteltetett marad, amíg a javított staging buildet a projektgazda el nem fogadja. A korábbi staging UAT nincs elfogadottnak jelölve; production nem változik.


## Hónap-/napválasztó átfedés és napi navigáció – 2026-10-13

Projektgazdai képernyőképes visszajelzés: a Hónap és Hét napja mezők egymásra csúsznak. A teljes szélességű szöveges magyarázat ugyanabban az auto-fit gridben tartotta nyitva az üres oszlopokat, és a natív hónapmezőnek nem volt minden szélességen min-width/max-width korlátja.

A tényleges szűrőmezők külön filterFields gridet kaptak; a magyarázat ezen kívül marad. Desktopon 220px-es minimális oszlopszélesség, minden controlnál min-width:0/max-width:100%; mobilon két rugalmas oszlop. A desktop oldal saját, scoped .page.stack szabálya oldalsó helyet hagy a klasszikus függőleges görgetősávnak, így nem jelenik meg a képernyőképen látott vízszintes túllógás. Globális CSS és napi naptár változatlan.

Kifejezett új UX-kérés: havi nézetben a napra kattintás rögtön a napi foglalási naptárt nyissa. Minden naplink most /foglalasok?datum=YYYY-MM-DD&room=UUID, view=month nélkül; a havi súgó ehhez igazodik. Ez nem foglaláslétrehozás és nem módosítja a jogosultságokat.

Ellenőrzés: Vitest 283/283 (új közvetlen napi navigáció render-regresszió); TypeScript PASS. Offline browser layout/navigáció: havi/foglalási lista/szabadidő-lista × 1920/1366/1280/1024/768/390/320px × normál/stabil scrollbar-gutter, magyar browser locale; 42/42 PASS. Minden input/select/button saját mezőhatáron belül, mezőpárok nem fedik egymást, nincs vízszintes túllógás. A DOM-ban minden havi naplink a megfelelő napi route-ra mutat. Ez szintetikus server render/CSS/DOM ellenőrzés, nem élő bejelentkezett staging UAT. A korábbi fixture a napi navigáció ellenőrzésén FAIL lett. A #291 draft a javított staging felhasználói elfogadásáig; production továbbra sem változik.
