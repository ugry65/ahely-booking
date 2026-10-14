# Múltbeli admin foglaláskorrekció nyitott hónapban

2026-10-14. Imre: az admin a nyitott hónap múltbeli foglalását tudja szerkeszteni,
például 08–17 helyett 09–17 használatra. Külön fejlesztés, a befizetésrögzítéssel
együtt ellenőrizhető stagingen; production GO nincs.

Napi naptár → múltbeli foglalás → Szerkesztés → kötelező korrekciós indok.
Csak a kiválasztott egyetlen alkalom módosulhat, sorozatban is. Ez új, explicit
kivétel a korábbi múltbeli sorozatszerkesztés tiltására; a jövőbeli sorozatművelet
három hatóköre változatlan. Régi UI baselineokat történeti bizonyítékként megőrizzük.
Az automatikus havi díj/óraszám újraszámolódik. A tényleges befizetés, foglaló,
egyedi booking óradíj és sorozatkapcsolat megmarad. Egyedi óradíj korrekcióját
továbbra is külön pénzügyi művelet kezeli, nem ez a szerkesztő.

DB: admin_correct_open_month_booking, aktív-admin guard, required reason,
eredeti updated_at optimistic check, payload/key idempotencia, room locks,
NO KEY UPDATE, sorted source/target period locks és closure recheck. Zárt
publikált hónap és legacy partial is_closed bármelyik érintett hónapban tiltott.
Az eredeti assert_booking_request és exclusion constraint védi a helyiségjogot,
nyitvatartást, időrácsot, minimum időt és ütközést. booking.updated before/after
audit kötelező indokkal, meglévő update/outbox/booking-email bridge contract.
Régi normál-user cutoff és pricing setter nem lazul. Korábbi receipt havi
hozzárendelése miatt befizetett booking hónapja nem cserélhető észrevétlenül.

Státusz: stagingen telepítve, a befizetésfejlesztéssel együtt átadható célzott
projektgazdai kipróbálásra. Production GO nincs, éles rendszer változatlan.

## Telepítési bizonyíték – 2026-10-14

- [PR #302](https://github.com/ugry65/ahely-booking/pull/302), main célág.
  Reviewed candidate `d83af72ce36659666f95fba241c16c507f21c04f`, main
  `1fb6234e46c19089c2c0895dd343fa5488b0acbb`; Git tree byte-exact egyezik.
- Staging projekt `prj_LzVgZgZBCAj4zA64YoYED3XkLGKW`, READY deployment
  `dpl_G82BKVwyPT78fAw1rgtftU41HjHc`, main SHA és stabil alias igazolt:
  https://ahely-booking-staging-web.vercel.app.
- [Application checks](https://github.com/ugry65/ahely-booking/actions/runs/38638768514),
  [Database tests](https://github.com/ugry65/ahely-booking/actions/runs/38638768431),
  [Release evidence](https://github.com/ugry65/ahely-booking/actions/runs/38638768422)
  SUCCESS a pontos jelöltön. 307 Vitest; 49 pgTAP fájl / 846 teszt, valamennyi
  concurrency és schema lint PASS. [Független APPROVE](evidence/2026-10-14-open-booking-correction/INDEPENDENT_REVIEW.md).
- Staging Supabase `fvwapntzhavhgazeflri`: actual migráció
  `20261014211856 / admin_open_month_booking_correction`; SQL MD5
  `a11ce7ccceb4d31f8303c338817ec5f7`. Canonical migration SHA256
  `2f3c15277d6670d7c3e89f53154dc5db9b5d20c444576f4bdd703844cdadcad9`.
  95 korábbi actual history sor változatlan; 96 soros új pin, projection pending `[]`.
  Régi UAT/adatmigrációt nem játszottunk újra, history-t nem javítottunk kézzel.
- Új RPC SECURITY DEFINER / üres search_path, anon EXECUTE=false,
  authenticated EXECUTE=true, belső active-admin guard. Function MD5
  `6c23d4ef8b1b9788ee3bdea652a4d022`. Advisor delta: egy új guarded-definer WARN
  (82→83); 32 deny-by-default RLS INFO és két meglévő Auth WARN változatlan.
- [Tranzakciós staging smoke](evidence/2026-10-14-open-booking-correction/staging-rollback-smoke.sql)
  PASS: szintetikus 08–17 → 09–17, 18000 Ft receipt megmarad, díj16000 Ft,
  havi túlfizetés2000 Ft. Minden fixture/audit/outbox ROLLBACK.
  Valós sorok változatlanok:452 booking,0 payment,12 settlement,14 revision,174 line.
  Booking hash `083edf81e2e8661692092ad8e58bc799`, payment hash
  `d41d8cd98f00b204e9800998ecf8427e`, revision hash
  `25d79e435e255206963cee8080f83843`, előtte/utána azonos.
- Stabil staging health HTTP200/database=ok; /foglalasok 307→/belepes.
  Telepítés utáni runtime error lekérdezés nem adott találatot.
  Ez technikai smoke, nem bejelentkezett kézi UI-UAT.
- Production ág továbbra `710f875a668ba3d87747ba227e29a82488754c4b`;
  production DB/config/email mód és üzleti adatok nem módosultak.

## Közös staging elfogadás

1. Admin naptár: nyitott hónap múltbeli foglalása → Szerkesztés → 09–17 és indok.
2. Havi összesítőben ellenőrizhető az óraszám és díj csökkenése.
3. Részleges vagy teljes befizetés rögzíthető; korrekció után a befizetett összeg
   megmarad, a fennmaradó összeg/túlfizetés újraszámolódik.
4. Lezárt hónap nem módosítható; múltbeli sorozatból csak az adott alkalom változik.

Projektgazdai elfogadás és külön élesítési engedély még nem érkezett.
