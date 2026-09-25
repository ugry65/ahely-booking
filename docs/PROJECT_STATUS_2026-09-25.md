# Projektállapot és hátralévő munka – 2026-09-25

Ez a dokumentum a 2026-09-25-i `main` állapothoz tartozó aktuális fejlesztési és release-pillanatkép. A régebbi dátumozott státuszdokumentumok történeti bizonyítékok; eltérés esetén ez a dokumentum, a projektkontextus és a jelenlegi `main` együtt értelmezendő.

## Aktuális forrásverzió

- `main`: `e3e719b9c3435f27ed9f82626ded87e21b44bb62`
- utolsó merge: PR #195 – CSS parser regresszió javítása a Migráció oldal szélességéhez;
- staging deployment: `dpl_HLBZVT6zSi9mBKyg2Sfbajeiphr6`, állapot: READY;
- canonical staging: `ahely-booking-staging-web.vercel.app`;
- production módosítás a 2026-09-24/25-i migrációs, XLSX- és UI-javítások során nem történt.

## 2026-09-24/25 között elkészült és ellenőrzött változások

### AllBooked/Skedda ügyfélmigráció

A generic együgyfeles import most már stagingen végponttól végpontig működőképes.

Elkészült:
- `Notes (Custom field 1)` megőrzése a `bookings.note` mezőben; üres érték → `null`;
- note nem duplikálódik audit payloadba és nem kerül a publikus naptár más felhasználónak látható read-modeljébe;
- staging write-import explicit engedélyezése úgy, hogy preview/feature/unknown target továbbra is fail-closed;
- dry-run és tényleges import UI egyértelmű szétválasztása;
- import-előfeltételek látható checklistje;
- Tréningterem-besorolás kész/összes darabszámának kijelzése;
- explicit `Mind egyéni` / `Mind csoportos` admin segédművelet, automatikus besorolás nélkül;
- pontos megerősítő szöveg külön megjelenítése;
- disabled importgomb vizuális megkülönböztetése;
- „atomi betöltés” helyett felhasználóbarát „biztonságos betöltés” megfogalmazás;
- Migráció admin oldal desktop szélességének javítása;
- a CSS-ben talált literal `\n` parser-hiba javítása és regressziós tesztje.

Staging üzleti UAT:
- a projektgazda 2026-09-25-én sikeresnek jelezte a tényleges importot;
- adatbázis utóellenőrzés: `alkalmifoglalas@gmail.com` profil létezik;
- pontosan 35 booking tartozik hozzá;
- 15 booking tartalmaz nem üres note-ot;
- időtartomány: 2026-09-04 – 2026-12-30;
- a booking e-mail outboxban ehhez a felhasználóhoz 0 job tartozik, tehát a migráció nem generált booking-emailt.

Kapcsolódó PR-ok: #187, #188, #192, #194, #195.

### Havi elszámolási összesítés XLSX export

Elkészült a valódi `.xlsx` export az Admin → Havi órák és elszámolás oldalon.

Tulajdonságok:
- ugyanazt a snapshot-aware `admin_monthly_pricing_summary` adatforrást használja, mint a képernyő;
- a kijelölt hónapokat exportálja;
- oszlopok: Hónap, Felhasználó, Összes óra, Fizetendő, Állapot, Revision;
- mindösszesen sor;
- valódi OpenXML/XLSX, nem átnevezett CSV;
- admin-only, `no-store`, részleges lekérdezési hiba esetén fail-closed;
- a szöveges cellák nem Excel-képletként kerülnek a fájlba;
- automatikus regressziós és integrációs teszt készült.

Kapcsolódó issue/PR: #189 / #190.

## Mi tekinthető késznek az első éles verzió szempontjából?

A jelenlegi `main` tartalmazza a napi foglalási alapfolyamatot, jogosultságokat, helyiségeket, egyedi és ismétlődő foglalást, módosítást/lemondást, Tréningterem-szabályokat, admin díjszabást, snapshot-aware havi elszámolási számítást, CSV/XLSX összesítést, együgyfeles AllBooked migrációt, booking e-mail outbox/worker kódot, health-checket és backup workflow-t.

A pricing célzott staging regressziós UAT 12/12 PASS. A generic AllBooked import stagingen valós, 35 foglalásos importtal igazolt. A korábbi foglalási UAT elfogadások érvényesek; változatlan funkciókat csak konkrét regresszió esetén kell újranyitni.

## Nyitott munka – prioritás szerint

### P0 – production indulás előtt kötelező release-gate

1. **Production backup frissesség és teljes restore-drill aktuális bizonyítéka.**
   A backup/restore mechanizmus korábban elkészült és volt sikeres bizonyíték, de éles indulás előtt az aktuális production mentés frissességét, off-site példányait, integritását és egy teljes visszaállítást újra release-evidence-ként rögzíteni kell. Adatvesztési kockázat miatt ez kötelező kapu.

2. **Production DB migrációs lánc egyeztetése és jóváhagyott deploy.**
   A stagingen alkalmazott új pricing, booking-email és AllBooked-note migrációkat össze kell vetni a production migration historyval. Production DB-módosítás csak külön projektgazdai jóváhagyással történhet.

3. **Booking e-mail production aktiválási kapu lezárása.**
   A kód mainben van és korábbi staging provider-UAT sikeres, de production DB-migráció/send nincs engedélyezve. Aktiválás előtt ellenőrizni kell a runtime módot, secret-nevek meglétét, pending backlogot/címzettkört, majd célzott staging provider-UAT bizonyítékot kell rögzíteni. Production `send` külön jóváhagyást igényel.

4. **Release candidate egyezés és célzott smoke.**
   A productionre kerülő commit SHA, DB migration history és environment konfiguráció egyezését rögzíteni kell; utána csak az érintett kritikus útvonalak célzott smoke-ja szükséges. Nem kell indokolatlanul újrafuttatni a már elfogadott, változatlan teljes UAT-ot.

### P1 – első valódi ügyfelek migrációjához szükséges operatív munka

5. **Ügyfelenkénti AllBooked migráció végrehajtása a runbook szerint.**
   A funkció elkészült; ez már nem fejlesztési hiány, hanem operatív adatátvétel. Minden ügyfélnél dry-run → Tréningterem-besorolás → exact confirmation → import → reconciliation → profil ellenőrzés → külön aktiváló/jelszóbeállító folyamat.

6. **Migrációs UAT bizonyíték megőrzése.**
   A 35 bookingos staging import eredményét jelen dokumentum rögzíti; production ügyfeleknél ügyfelenként minimális, érzékeny adatot nem duplikáló reconciliation bizonyíték szükséges.

### P2 – nem launch-blocker, későbbi fejlesztés / backlog

7. **Teljes pénzügyi befizetés/korrekció modul.**
   Részfizetés, fizetési mód/célhely, befizetett/fennmaradó összeg, státusz, auditált korrekció továbbra is későbbi fázis az implementációs terv szerint. A jelenlegi pricing/summary nem azonos a teljes pénzügyi nyilvántartással.

8. **Mobil menüpont-oldalak teljes reszponzív finomítása (#109).**
   A foglalási naptár mobil baseline-ja elfogadott. A további admin/menüpont-oldalak általános reszponzív finomítása külön backlog; a Migráció oldal konkrét desktop-szélesség hibája már javítva.

9. **PWA (#105).**
   Nem első éles verziós blocker.

10. **Heti naptárnézet.**
    A napi többhelyiséges nézet az elfogadott első verziós minimum; heti nézet későbbi lehetőség.

11. **Több ügyfél egy CSV-ben történő migráció.**
    Jelenleg szándékosan nem támogatott és nem szükséges az első éles induláshoz. Az egy ügyfél/fájl modell a production runbook része.

12. **Kihasználtsági/statisztikai dashboard, számlázó-integráció, Google Calendar egyirányú szinkron.**
    Későbbi fázisok; a foglalási adatbázis marad az authoritative forrás.

## GitHub issue-higiénia

A nyitott issue-listában több történeti umbrella/implementációs issue továbbra is nyitva látszik annak ellenére, hogy a kapcsolódó funkció részben vagy teljesen elkészült. Ezeket nem szabad automatikusan „hátralévő fejlesztésnek” tekinteni. Külön issue-audit szükséges: kész issue-k lezárása vagy scope-juk pontosítása, a valóban nyitott release-gate-ek megtartása. Különösen felülvizsgálandó: #31, #36, #73, #75, #82, #100–#104, #107, #116, #150.

## Production biztonsági szabály

A dokumentáció frissítése, main merge és staging deployment nem jelent production engedélyt. Production adatbázis-, environment-, e-mail send- vagy üzleti adatmutáció csak külön, kifejezett projektgazdai jóváhagyással történhet.
