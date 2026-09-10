# Claude review 5 – closure státusz

Dátum: 2026-08-26  
Branch: `fix/claude-review-3-closure`  
PR: #91

## Review eredmény és validálás

Az 5. független adversarial review a vizsgált
`afba25382016c5d63a9878a3bc92c85ac26c539a` HEAD-et 100%-os
funkcionális/dokumentációs closure-re alkalmasnak minősítette, P0/P1/MEDIUM+
finding nélkül.

A review `RESIDUAL RISK` fejezete ugyanakkor konkrétan igazolta, hogy
privilegizált vagy `service_role` adatbázis-kapcsolat utólag új
`settlement_booking_lines` sort tudott beszúrni egy már lezárt revisionbe,
mert a védelem csak UPDATE és DELETE műveletre vonatkozott.

Ezt nem fogadtuk el nem blokkoló kockázatként. A kanonikus baseline szerint a
lezárt történeti settlement snapshot kontrollálatlanul nem változhat; új sor
utólagos hozzáfűzése ugyanúgy megváltoztatja a snapshot pénzügyi tartalmát, mint
egy UPDATE vagy DELETE. Az invariáns DB-szintű, ezért nem korlátozható kizárólag
az `authenticated` threat modelre.

## MEDIUM – lezárt snapshot append-módosítása

**Státusz: CLOSED a `70531c388ce9ef834a43df05ada14076f8bfbb3c` commitban.**

Előrehaladó migráció:

`supabase/migrations/20260826205749_protect_closed_settlement_line_inserts.sql`

A javítás három egymást erősítő DB-invariánst vezet be:

1. már lezárt revisionhöz új `settlement_booking_lines` sor nem fűzhető;
2. már lezárt `monthly_settlements` rekordhoz új `settlement_revisions` sor nem
   fűzhető;
3. lezárás után az `is_closed`, `closed_at`, `closed_by` és
   `closed_revision_id` lezárási metaadatok nem nullázhatók vagy cserélhetők.

A payment backend továbbra is módosíthatja a nem lezárási mezőket, például a
`status` és `updated_at` értéket. A legitim lezárási RPC működése változatlan:
a revision és booking-line sorokat a settlement lezárt állapotba állítása előtt,
ugyanabban az adatbázis-tranzakcióban készíti el.

## Regressziós bizonyíték

A `supabase/tests/database/084_settlement_snapshot.sql` pgTAP terv 24
asszercióra bővült. Privilegizált teszt-sessionből bizonyítja, hogy:

- lezárt snapshothoz booking-line INSERT `42501` hibával elutasított;
- a sikertelen INSERT után a snapshot sorszáma változatlan;
- lezárt settlementhez revision INSERT `42501` hibával elutasított;
- a lezárás és a `closed_revision_id` kapcsolat utólagos nullázása `42501`
  hibával elutasított;
- a korábbi UPDATE- és DELETE-védelem változatlanul működik;
- a normál `admin_close_monthly_settlement` lezárási folyamat továbbra is
  sikeres.

A próbák `reset role` után futnak, ezért nem RLS vagy kliensoldali GRANT miatt
kapnak hibát, hanem a DB-trigger invariánsait bizonyítják.

## Ellenőrzött CI

A javított `70531c388ce9ef834a43df05ada14076f8bfbb3c` HEAD-en:

- Database tests run #402, ID `33013383321`: **SUCCESS**;
- tiszta Supabase DB-indítás és teljes migráció-reset: **PASS**;
- teljes pgTAP csomag: **PASS**;
- minden booking/jogosultsági concurrency teszt: **PASS**;
- schema lint: **PASS**;
- Vercel preview check: **SUCCESS**.

## Következő kapu

A review 5 által kimondott closure a review saját residual-risk megállapítása
miatt nem volt változtatás nélkül elfogadható. A rés kód- és tesztszinten
lezárult, de a HEAD megváltozott, ezért a végső 100%-os closure-hez még egy
független adversarial review szükséges a javított legfrissebb HEAD-en.

Ez továbbra sem production GO. A manuális staging UAT, backup/restore,
monitoring/alert drill és explicit üzleti jóváhagyás külön kapuk.
