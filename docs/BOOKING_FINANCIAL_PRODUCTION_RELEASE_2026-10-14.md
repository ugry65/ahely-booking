# Foglalási befizetések és admin korrekció – production kiadás

2026-10-14. Imre 23:35 Europe/Budapest: „A funkciók működnek.”
A kapcsolódó működés ellenőrzésének feltételével élesítést engedélyezett.
Ez a közös #300/#302 staging elfogadás; nem alkotunk utólag tételes kézi UAT-t.
[Elfogadás forrása](https://github.com/ugry65/ahely-booking/pull/302).

## Kiadott változat

- [Production PR #304](https://github.com/ugry65/ahely-booking/pull/304), main → production.
- Elfogadott main/staging SHA `0f9e4a543b2d8c56cb30c4503339be4274fe8aa6`;
  staging READY `dpl_J5PaKLB4R7RhVGA4TjHoJ5DyC28w`.
- Production SHA `ea46cacdfaf61ead042b5187c79588300df66c67`;
  READY `dpl_FFGkcfaWwFKyKsQZ8e5RbRhgghKE`, projekt
  `prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo`, alias https://foglalas.a-hely.com.
  Production és elfogadott main tree byte-exact azonos:
  `a9a94f3e6193cdaaa56c6f9002e118cb4637d186`.
- Production release gate run38641549084, Application checks run38641549030,
  Release evidence run38641548995, Database tests run38641549174,
  isolated schema run38641548978: SUCCESS a pontos main jelöltön.
  307 Vitest,846 pgTAP, teljes concurrency suite és schema lint PASS.
- Független reviewer booking_payment_review: source GO, majd actual production
  függvényfüggőségek GO. require_active_admin/assert_booking_request/
  calculate_monthly_pricing/month_normal_minutes egyező definíciók.
  resolve_booking_applied_rate, admin_create_monthly_settlement_revision és
  guard_published_settlement_booking_write komment/formatálás eltérés;
  close függvényben stagingen csak egy használatlan deklaráció többlet.
  SQL-tokenek, zárolás és pénzügyi üzleti szabályok egyeznek. Nem szükséges repair.

## Hatáskör

A befizetésrögzítés, érvénytelenítés, havi egyenleg és export admin felülete
aktív. Nyitott havi pénzügyi kimutatás élő booking adatot, lezárt kimutatás az
aktív closed revisiont használja. A múltbeli admin korrekció indokolt, egyetlen
alkalmat szerkeszt; fizetés/owner/egyedi óradíj/series megmarad. Normál user
cutoff, ütközés, díjszabás és zárt hónap védelme megőrzött. Érvényes befizetéssel
booking tulajdonos/hónap váltás tiltott, külön pénzrendezés szükséges.
Felhasználói végleges havi kártya, számlaküldés és banki művelet nem változik.

## Production adatbázis

Kizárólag `yasrmxwjojepessivhmc`, DB-first sorrendben két reviewed migráció:

| Actual version | Név | SQL MD5 |
| --- | --- | --- |
| 20261014214018 | booking_payments | 2f72b1361b6973cf500303c08ecec0f0 |
| 20261014214025 | admin_open_month_booking_correction | a11ce7ccceb4d31f8303c338817ec5f7 |

Canonical SQL SHA256: payment
`3de17bbab2514d2c812465effa30a0036026409429a6ebc16d80a60c8d2eff98`;
historical `2f3c15277d6670d7c3e89f53154dc5db9b5d20c444576f4bdd703844cdadcad9`.
91 régi actual history sor változatlan, új history93. Nincs történeti replay,
history repair, pénzügyi backfill vagy meglévő booking módosítás.
13 új/módosított RPC/trigger funkció MD5-je egyezik staginggel; publikus admin
RPC-k anon EXECUTE=false, authenticated=true, belül active-admin guard;
trigger helper execute=false. payments/payment_voids RLS=true és közvetlen
authenticated SELECT/INSERT/UPDATE/DELETE=false. Snapshot és overlap/FK
constraintok és ledger egyediségek ellenőrizve.

Synthetic production BEGIN/ROLLBACK smoke PASS: 08–17 → 09–17 korrekció,
18000 Ft befizetés megmarad, új díj16000 Ft, havi túlfizetés2000 Ft. A smoke
a reviewed staging SQL-t használta új UUID-kkel, STRICT/NULL-safe assertionökkel;
minden synthetic auth/profile/room/booking/payment/audit/outbox írás rollback.
Ez technikai DB smoke, nem bejelentkezett production UI-UAT.

Valós adatok darabszáma és teljes sorhash-e előtte/utána azonos:

| Tábla | Sor | MD5 |
| --- | ---: | --- |
| bookings | 2161 | 7ec36adfef110958a120fc20e7c7bc85 |
| payments | 0 | d41d8cd98f00b204e9800998ecf8427e |
| monthly_settlements | 52 | 43db5569d09c022759af1139fa69f167 |
| settlement_revisions | 63 | 50004f9c7ebae1677d22ebb0a9ba5db7 |
| settlement_booking_lines | 883 | 663d28d4ba53fa39268d15ad9ca5cfc1 |
| settlement_adjustments | 0 | d41d8cd98f00b204e9800998ecf8427e |
| monthly_settlement_periods | 1 | 051d4a377a5b08c21633bcc1cb8b8032 |

Payment hash az új nullable booking_id nélkül számított; meglévő mezők védve.
Advisor delta várt: deny-by-default RLS INFO31→32, guarded definer WARN73→82,
két korábbi Auth WARN változatlan. Új nem várt security finding nincs.

## Élő ellenőrzés és visszaállítás

Production BOOKING_EMAIL_MODE aktuális konfigurációja read-only lekérdezéssel
`disabled`, változatlan. Titok/config módosítás és értesítésküldés nem történt.
Domain health HTTP200 / database=ok, admin/havi-orak 307→belepes. Telepítés
utáni runtime error lekérdezés üres. Web rollbacknél az additive adatbázissémát
és az esetleg újonnan rögzített pénzügyi adatot meg kell őrizni; pénzügyi rekord
fizikai törlése és migráció-visszajátszás tilos. Rövid DDL zárolás lehetséges;
teljes kockázatmentességet a tesztek sem bizonyítanak.
