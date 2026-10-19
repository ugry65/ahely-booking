# Részleges lemondás – 2026-10-19

Imre kifejezetten staging megvalósítást kért új és meglévő tömbös foglalásokra.
Példa: ma09:00, holnap08–15, lemondandó10–12. A cutoff a kivett rész kezdete,
nem a teljes tömb08:00 kezdete. Óránkénti kijelölés, megerősítés előtt a
megmaradó8–10/12–15 előnézete. Több különálló kijelölés is egy tranzakció.

Állapot: feature draft, NINCS stagingre vagy productionre telepítve.

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

Root-group advisory → room advisory → ledger FK → sorted root/selected
NO KEY UPDATE NOWAIT → period advisory → closure/cutoff recheck. A NOWAIT
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
