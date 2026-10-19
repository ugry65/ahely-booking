# Részleges lemondás – 2026-10-19

Imre kifejezetten staging megvalósítást kért új és meglévő tömbös foglalásokra.
Példa: ma09:00, holnap08–15, lemondandó10–12. A cutoff a kivett rész kezdete,
nem a teljes tömb08:00 kezdete. Óránkénti kijelölés, megerősítés előtt a
megmaradó8–10/12–15 előnézete. Több különálló kijelölés is egy tranzakció.

Állapot: stagingre telepítve, projektgazdai kipróbálásra átadva. Production GO nincs.

## Biztonsági modell

Eredeti booking ID az első megmaradó résznél marad; további részek flat
root_booking_id-val kapcsolódnak hozzá, az eredeti blokkot a ledger/audit
before snapshot őrzi. Érintetlen foglalásokat nem migrálunk át előre.
Receipt változatlan, csoportszintű context/history, havi pénz egyszer számít.
A tételes kimutatás a közös pénz/fennmaradó összeg/túlfizetés összegét csak egy
anchor soron mutatja; a közös csoport azonosítója és státusza minden részen látszik.
Owner és Budapest hónap csoporton belül nem változhat. Másolat nem örököl groupot.
Óradíj override és meglévő legacy tréningdíj a maradékokra változatlanul átkerül.

Időrács/minimum DB-beállításból; 60 percnél rövidebb maradék nem jön létre.
Egy utolsó félórás rész lemondása akkor megengedett, ha a megmaradó rész eléri
a minimumot. Alapórás UI a meglévő kezdésből indul, a végső félórát külön jelzi.
Backend az összes range tartalmazását/grid/finite/rendet/cutoffot ellenőrzi.
Lezárt vagy legacy részlegesen lezárt hónap nem bontható fel adminként sem.

Root-group advisory → room advisory → root/selected NO KEY UPDATE NOWAIT
→ ledger FK → period advisory → closure/cutoff recheck. A NOWAIT
részenként zároló régi sorozatműveletnél holtpont helyett teljes rollbacket és
újrapróbálható üzenetet ad. Payload-normalizált
idempotencia és optimista updated_at; eredeti cutoff csak az új privát ledger
folyamatban, transaction_id és pontos booking verzió mellett enged kivételt.
Ütközésvédelem DB exclusion; pénzügyi/snapshot sor fizikailag nem törlődik.

Month-close a legkésőbbi rács szerinti még lemondható részt is vizsgálja, így nem
veheti el a felhasználó érvényes részleges lemondási lehetőségét.
Új semantic booking.parts_cancelled audit/outbox, nem hamis teljes lemondás.
A booking-email production disabled módja változatlan; új emailküldés nincs.

Sorozatból csak az adott alkalom részleges lemondása támogatott. A felbontott
alkalom részei külön szerkeszthetők; a teljes sorozat időtartamának átírását
az új trigger tiltja, hogy ne tömörítse össze a megmaradó eltérő részeket.
Sorozat törlése és az érintetlen sorozatok korábbi három hatóköre megmarad.
Ez dokumentált új kivétel; a korábbi UI baseline történeti állapotát nem írjuk át.
Sticky/scroll/longpress/7napos sáv/gyorsfoglalás változatlan.

## Kötelező kiadási kapuk

- pgTAP: közép/szél/teljes/ismételt felbontás, több kijelölt rész, határidő,
  jogosultság, minimum, zárt hónap, pénzmegőrzés és exportduplázás.
- Valós concurrency: double submission, competing edit/create, close és payment.
- Normál foglalási, sorozat-, díjszabási, publication-, financial regresszió.
- Független kritikus review és csak a végleges SHA-n sikeres CI.
- Staging actual history/source egyeztetés; kizárólag reviewed új SQL, történeti
  UAT/adatmigráció replay nélkül; rollback smoke és adatmegőrzés.
- Pontos staging READY SHA és link; production csak külön későbbi GO-val.

## Staging kiadás – 2026-10-19

- Reviewed candidate: `f652c6a0dea98529972d2d3691dfaa7d1f2beb55`, PR #306.
- Main/staging: `84f1970a2ad9ee35b44d8f27bb9547db6092aa95`.
- READY: `dpl_98RYCjjqsix4kffX7dAjNjHmefC2`; projekt
  `prj_LzVgZgZBCAj4zA64YoYED3XkLGKW`, main SHA és stabil alias igazolt.
- Link: https://ahely-booking-staging-web.vercel.app/foglalasok
- CI: Application checks 39318632353, Database tests 39318632389,
  Release evidence 39318632415, schema inventory 39318632422 mind SUCCESS.
  316 Vitest, 886 pgTAP assertion, régi és új concurrency tesztek PASS.
- Actual staging migration: `20261019202704/partial_booking_cancellation`.
  Raw SQL MD5 `bd1fa03fe3c472dc56ca271c678a8d79`, canonical SHA256
  `1eac36adf985a9fa860abffa9f58391c3981dad090e11ffbe2b7cd331c7beef8`.
  96 korábbi history sor változatlan; pontosan egy új migration, nincs replay/repair.
- Rollback DB smoke: owner 08–15 foglalásból 10–12 lemondás → két rész,
  összesen 300 perc. 14 000 Ft befizetés megmarad, új díj 10 000 Ft,
  export egyszer számolja a pénzt, havi túlfizetés 4 000 Ft. Minden fixture rollbackelve.
- Adatmegőrzés: bookings452/payments1/monthly_settlements13/revisions14/
  booking_lines174/periods1, valamennyi normalizált sorhash előtte/utána azonos.
- Új ledger RLS bekapcsolva, anon/authenticated közvetlen hozzáférés nincs.
  Belső helper RPC-k execute joga mindkét szereptől tiltott; új publikus RPC csak
  authenticated számára elérhető, aktív owner/admin ellenőrzéssel.
- Security advisor delta: szándékos deny-by-default ledger INFO +1,
  guarded authenticated SECURITY DEFINER RPC WARN +1. Két korábbi Auth WARN
  változatlan; konfigurációt nem módosítottunk.
- HTTP health200/database=ok; védett naptár307→/belepes; indulás utáni
  runtime error lekérdezés üres. Ez nem bejelentkezett böngészős UI-UAT.
- Független review: [INDEPENDENT_REVIEW.md](evidence/2026-10-19-partial-cancellation/INDEPENDENT_REVIEW.md).
- Production ág `ea46cacdfaf61ead042b5187c79588300df66c67` változatlan;
  production SQL/config/email aktiválás nem történt.

Kipróbálás: foglalás menü → Órák lemondása → órák kijelölése → megmaradó
részek előnézete → megerősítés. Régi és új tömbök azonos módon kezelhetők.
Határidőn belüli rész, jogosulatlan felhasználó vagy lezárt hónap nem engedett.

Rollback megjegyzés: a csoportosított foglalások létrejötte után a pénzügyi
read model nem állítható vissza csoportokat nem ismerő régi verzióra egyszerű
webes rollbackkel. Additív sémát, ledger- és befizetési sorokat meg kell őrizni.
