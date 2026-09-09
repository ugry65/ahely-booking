# AllBooked → A-Hely migrációs mapping

Dátum: 2026-09-09
Kapcsolódó issue: #108

## Cél

Ez a dokumentum a jelenlegi AllBooked exportokból az A-Hely saját foglalási rendszerébe történő migráció forrás→cél megfeleltetését rögzíti. A migráció reprodukálható, stagingen újrafuttatható, dry-run alapú és reconciliationnel ellenőrzött folyamat.

## Időbeli scope

A végleges üzleti döntés szerint az első migráció:

- a migráció hónapjának teljes adatkörét a hónap első napjától;
- valamint minden jövőbeli szükséges adatot/foglalást

emel át. A migráció hónapját megelőző történeti hónapok nem részei az első scope-nak.

## Pénzügyi mezők – kötelező kizárás

Az AllBooked forrásrendszer óradíj- és áradatai nem célrendszeri pénzügyi források. Az A-Hely új rendszerében más havi sávok és díjszámítási szabályok érvényesek.

Ezért az alábbi mezők importkor figyelmen kívül maradnak, és reconciliation során sem hasonlítjuk őket a célrendszer díjaihoz:

- `Total booking price`
- `Payment status`
- `Line item price`
- `Gateway charge reference`
- minden olyan legacy tag, amely pusztán régi óradíjat jelöl (például `1700`)

A migrált foglalások díjazását kizárólag az A-Hely célrendszer aktuális díjszabályai számítják. Tréningterem esetén is a célrendszer speciális üzleti szabálya az irányadó; legacy ár nem írhatja felül.

## User mapping

| AllBooked forrás | A-Hely cél | Szabály |
| --- | --- | --- |
| `Holder first name` | `profiles.first_name` | trim; kötelező |
| `Holder last name` | `profiles.last_name` | trim; kötelező |
| `Holder email` | Auth + `profiles.email` | lowercase + trim; elsődleges természetes egyeztetési kulcs |
| `Holder telephone` | `profiles.phone` | normalizálás szükséges; a `Tel:` előtag nem része az értéknek |
| `Holder organization` | csak külön igazolt célmező esetén | üres érték nem generál adatot |
| AllBooked aktív/inaktív státusz | `profiles.is_active` | csak megbízható exportmezőből; a booking export önmagában nem bizonyítja |
| admin szerep | `profiles.role` | csak explicit user exportból; alapértelmezés nem képezhető booking exportból |
| `Holder tags` | helyiségcsoport/jogosultság mapping | kizárólag explicit mapping szerint; numerikus ár-tag nem jogosultság |

### Papp Dalma reprezentatív minta

A 2026-09-09-én kapott booking export alapján:

- név: Papp Dalma;
- e-mail: `pappdalma17@gmail.com`;
- telefon forrásérték: `Tel: 06 30 733 7981`;
- tagek: `1700, Forrás`;
- `Forrás` üzleti jelentése a kézi user-képernyő alapján helyiség-hozzáférésként kezelendő;
- `1700` legacy díjtag, migrációs pricing policy nem képezhető belőle.

## Booking mapping

| AllBooked forrás | A-Hely cél | Szabály |
| --- | --- | --- |
| `Scheduled start` | `bookings.start_at` | Europe/Budapest lokális időként értelmezendő, majd időzónás célértékre konvertálandó |
| `End` | `bookings.end_at` | Europe/Budapest; `End > start` kötelező |
| `Duration (minutes)` | ellenőrző mező | `End - Scheduled start` egyezés kötelező; nem külön célforrás |
| `Holder email` | `bookings.user_id` | user mapping e-mail alapján |
| `Spaces` | `bookings.room_id` | explicit kanonikus room mapping; ismeretlen érték elutasítandó |
| `Line item name` | ellenőrzés | Space típusnál egyezzen a `Spaces` értékkel |
| `Booking type` | importvalidáció | támogatott típusok explicit listája szükséges |
| `Booking title` | booking title | ha üres, a migrációs szabály szerinti biztonságos default szükséges; nem található ki forrásadatból |
| `Notes (Custom field 1)` | csak explicit döntés alapján | személyes/szenzitív tartalom miatt nem másolandó automatikusan |
| `Created` | migrációs provenance | forrás-metaadatként használható; nem cél booking kezdési idő |
| `Spaces count` | ellenőrzés | első scope-ban pontosan 1 támogatott; eltérés riportba kerül |
| `Add-Ons count`, `Add-Ons` | első scope-ban nem támogatott | nem nulla/nem üres érték külön eltérésként riportolandó |

## Room mapping – első reprezentatív minta

| AllBooked | A-Hely kanonikus cél |
| --- | --- |
| `Forrás tér` | `Forrás tér` |

A tényleges import nem végezhet általános névegyezést: minden új forráshelyiséghez explicit mapping szükséges a 11 kanonikus célhelyiség egyikére.

## Reconciliation

A forrásrendszer pénzösszegei nem részei a reconciliationnek. Kötelezően összevetendő:

- user darabszám és aktív user darabszám;
- userenként booking darabszám;
- helyiségenként booking darabszám;
- userenként havi óraszám;
- foglalások kezdete, vége és időtartama;
- jövőbeli foglalások tételes egyezése;
- ismétlődő sorozatok és kivételek száma, ha a forrás megbízhatóan exportálja;
- Tréningterem foglalások külön kontrollja;
- elutasított/ütköző rekordok: 0 vagy külön jóváhagyott kivétellista.

## Első staging próba

A Papp Dalma booking export 21 sort tartalmaz, egyetlen userrel és egyetlen helyiséggel (`Forrás tér`), 60 és 90 perces foglalásokkal. Ez megfelelő reprezentatív első dry-run és staging import mintának.

Az első implementációs egység kizárólag parser + normalizálás + dry-run riport. Adatbázisírás csak ennek automatikus tesztje és ellenőrzése után következhet.
