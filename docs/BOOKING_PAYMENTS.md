# Foglaláshoz kapcsolt befizetések

2026-10-14. Követelmény és staging-megvalósítás. Production GO nincs.

Imre jóváhagyott igénye: alapból nem fizetett foglalások, csak admin által
rögzíthető befizetés, havi részfizetés/teljes fizetés kimutatása. Az összeg
nyilvántartása szükséges a változó havi díjsáv és a részfizetés miatt.

## Használat

- Napi naptár → foglalás → **Befizetések**, kizárólag adminnak.
- Admin → Havi órák és elszámolás → tételes sor → **Befizetések**;
  mobilon ugyanitt a kártyán elérhető.
- Átvett összeg, dátum, fizetési mód, célhely és opcionális megjegyzés.
- Alapérték készpénz, célhely készpénz. A rendszer nem indít banki műveletet.
- Részfizetés több befizetési rekorddal rögzíthető.
- Téves rögzítés indoklással/megerősítéssel érvényteleníthető, nem törölhető.
  Ez nem tényleges pénzvisszafizetés. Javítást új, helyes rögzítés követhet.
- Havi befizetési összesítés: havi díj, befizetve, fennmaradó, túlfizetés,
  fizetési állapot. Nyitott hónapban előzetes; lezárt hónapban snapshot díj.
- A havi adminnézet és export közös új read-modelt használ: a nyitott hónap
  mindig élő adat, a lezárt hónap az aktív lezárt revision. A korábbi, lezárás
  előtti draft revision megmarad a történetben, de nem fedheti el az új foglalást.
- Az összesítő export fizetendője a pénzügyi korrekciókat is tartalmazza;
  a részletes foglalási sorok továbbra is a foglalások díját mutatják.
- Összesítő CSV/Excel és részletes CSV pénzügyi oszlopokkal bővül.
  A korábbi revision/elszámolási állapot exportoszlopok nem térnek vissza.

## Adatmodell és védelem

Egy befizetés egy `payments` rekord; opcionális `booking_id` kapcsolja
az alkalomhoz. A korábbi havi befizetések is beleszámítanak, duplázás nélkül.
`payment_voids` append-only érvénytelenítési napló. Csak aktív admin RPC-k,
üres search_path, explicit ACL, RLS és közvetlen kliensírás-tiltás.
Idempotenciakulcs/payload-ellenőrzés, user/hónap tranzakciós zárolás és audit.
Lezárt revision és foglalási díjszabás nem változik a pénz rögzítésétől.

A lemondás nem törli az átvett pénzt: havi jóváírás/túlfizetésként megmarad.
Érvényes befizetéssel a foglaló vagy az elszámolási hónap nem cserélhető
észrevétlenül; külön pénzrendezés szükséges. Duplikált foglalás nem örököl pénzt.
Ismétlődő foglalásnál a befizetés mindig az egyetlen kiválasztott alkalomé.

Az alkalmi gyűjtőfiókok havi összesített egyenlege fiókszintű; az egyedi
alkalmak befizetése a foglalási oldalon és a részletes CSV-ben követhető.
Korábbi befizetés nélküli adatokat nem jelölünk utólag fizetettnek.
Számlázás/kiküldés és a felhasználói végleges havi kártya most nem változik.

## Ellenőrzés és kiadás

Helyi typecheck és Vitest: PASS, 306 teszt. Feature jelölt:
`03b0c6b4df2c464feedb2f7d9955e6bd24c8feda`, PR #300. Független review
APPROVE: [INDEPENDENT_REVIEW.md](evidence/2026-10-14-booking-payments/INDEPENDENT_REVIEW.md).
Application run38605440626, evidence run38605440535, isolated-reference
run38605440512 és DB run38605440586 SUCCESS. DB job115994988514:
48 pgTAP fájl / 822 teszt és teljes concurrency suite PASS, az új
snapshot/befizetés mindkét sorrend és void/havi writer teszttel együtt.

## Staging átadás – 2026-10-14

- #300 main merge: `fd434a7d04ceabbd5304b7745ddefd09f89ab4d1`.
- Staging Vercel `prj_LzVgZgZBCAj4zA64YoYED3XkLGKW`, READY
  `dpl_4vvd283VjdmUsneamCuENukcGJby`, pontos main SHA és stabil alias igazolt.
- Használat: https://ahely-booking-staging-web.vercel.app/admin/havi-orak
- Supabase kizárólag staging `fvwapntzhavhgazeflri`. Projection guard94
  byte-exact történeti sor, kizárólag az új migration pending. Reviewed SQL
  egy normál apply_migration hívással alkalmazva; actual `20261014172144`,
  név `booking_payments`, MD5 `2f72b1361b6973cf500303c08ecec0f0`.
  Canonical SHA256 `3de17bbab2514d2c812465effa30a0036026409429a6ebc16d80a60c8d2eff98`.
  A94régi historysor változatlan; új pin95. Nincs replay/history repair.
- Nyolc új publikus RPC SECURITY DEFINER/üres search_path, authenticated execute,
  anon-tiltás ellenőrizve; belül aktív admin szükséges. payment_voids RLS+ACL tiltás.
- Staging transactional smoke: izolált fixture booking, receipt1000,
  booking-context/monthly balance1000, void után0 PASS. Minden fixture rollback.
- Üzleti adat változatlan: 452 booking,0 payment,12 settlement,14 revision,
  174 line. A pénzügyi snapshotok teljes sorhash-e egyezik;0void maradt.
- Health HTTP200 ok/databaseok, admin route307→belepes; indulás utáni runtime
  error aggregáció üres. Ez technikai smoke, nem bejelentkezett böngészős UI-UAT.
- Advisor: deny-by-default RLS INFO31→32, guarded definer WARN74→82 a nyolc
  admin RPC miatt; Auth figyelmeztetések változatlanok. Nincs új nem várt jelzés.
- Production ág/DB/konfiguráció/e-mail mód nem módosult. Élesítés külön GO után.
