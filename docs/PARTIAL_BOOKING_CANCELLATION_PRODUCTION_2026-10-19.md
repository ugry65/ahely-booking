# Részleges foglaláslemondás – production kiadás

2026-10-19, Europe/Budapest. Állapot: production READY, technikai ellenőrzések PASS.

Imre 23:02:16: „a megoldás tetszik, elfogadom”; az elszámolási ellenőrzések
ismertetése után 23:03:16: „akkor élesíthető”. Ez a végleges staging megoldás
projektgazdai elfogadása és explicit production GO; nem utólag kitalált tételes UAT.

## Elfogadott verzió és működés

- [Release PR #312](https://github.com/ugry65/ahely-booking/pull/312), main → production.
- Elfogadott main/staging SHA `c1c3bf9674c87722ad81f0757d1745edc0134e0f`.
- Staging READY `dpl_FeJVbcKXai5qeDo2bEbd8J1VH2SZ`, stabil alias és exact SHA igazolt.
- Implementáció #306, kijelölési és adatvédelmi finomítások #308–#311.
- Órás elválasztás a tömbön, félórás részek kijelölése és megmaradó előnézet.
  A jelölő az időpont mellett jelenik meg, a teljes sora kattintható.
- A határidő a lemondott rész kezdetére vonatkozik; aktív admin kivételt kap.
  Lezárt havi részleges lemondás admin számára is tiltott.
- Egyórás foglalásnál csak „Teljes foglalás törlése”; hosszabb foglalásnál
  „Órák lemondása” is. A megmaradó részek legalább 60 percesek.
- Lemondásnál személyes indoklást egyik ablak sem kér. Műveleti audit megmarad.
- A sorozat részleges lemondása az adott alkalmat érinti. A már felbontott
  alkalom részenként szerkeszthető; egész sorozatot átíró időtartammódosítás tiltott.
- Megmaradt időszakok adják a díjat; rögzített befizetés megmarad, csoportonként
  egyszer szerepel az exportban. Havi tartozás/túlfizetés újraszámolódik.

## Tényleges production eredmény

- Production SHA `8c1f10412167c4708ec900ccc1779351b60121a3`.
- READY `dpl_7AkeBJsrn5nKCQeroGKoi4itWLiA`, projekt
  `prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo`, domain https://foglalas.a-hely.com.
- Production és elfogadott staging tree egyaránt
  `51ec8c66ed1bea2160c967697b7af17c2f422fcb`; forrásazonosság igazolt.
- Exact candidate CI: release gate39324570433, application39324570438,
  evidence39324570409, database39324570495, schema39324570361 mind SUCCESS.
  317 Vitest,886 pgTAP, teljes concurrency suite PASS. Külön partial concurrency:
  valódi legacy series-verseny, azonos párhuzamos kérések, payment és mindkét
  month-close sorrend sikeres.
- Actual migration `20261019211049/partial_booking_cancellation`, raw SQL MD5
  `bd1fa03fe3c472dc56ca271c678a8d79`. Korábbi93 history sor változatlan, új history94.
- Mind15 létrehozott/átnevezett függvény törzse, argumentumai, security-definer
  és search_path beállítása staginggel egyezik.
- Új RPC anon EXECUTE=false/authenticated=true, belül active owner/admin guard.
  Belső helper execute anon/authenticated=false. Ledger RLS=true, közvetlen
  anon/authenticated SELECT/INSERT/UPDATE/DELETE=false.
- Production BEGIN/ROLLBACK smoke PASS: owner 08–15 blokkból 10–12 lemondása
  után két rész és300 perc; rögzített2000Ft/óra →10000Ft díj,14000Ft befizetés
  változatlan, exportban egyszer, havi túlfizetés4000Ft. A reason null, ahogy a
  végleges UI-ban is. Új synthetic UUID-k; minden fixture írás rollbackelve.
  [Futtatott SQL](evidence/2026-10-19-partial-cancellation/production-rollback-smoke.sql).
- A lenti nyolc üzleti tábla darabszáma és normalizált sorhash-e előtte/utána
  azonos. Meglévő foglalás/pénzügyi adat/snapshot nem változott a migrációtól.
- Security advisor delta: private deny-by-default ledger INFO32→33;
  guarded authenticated RPC WARN82→83; két korábbi Auth WARN változatlan.
  [RLS magyarázat](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
  [RPC magyarázat](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- Környezeti változó, email mód, titok vagy scheduler módosítása nem történt.
- Élő health HTTP200/database=ok; védett naptár307→/belepes. READY utáni
  runtime-error lekérdezés üres. Ez technikai ellenőrzés, nem bejelentkezett
  production UI-UAT.

## Független ellenőrzés és adatbázis-előfeltételek

SQL source SHA256 `1eac36adf985a9fa860abffa9f58391c3981dad090e11ffbe2b7cd331c7beef8`;
reviewed source `f652c6a0dea98529972d2d3691dfaa7d1f2beb55`.
A későbbi UI-jelöltek külön SHA-hoz kötött APPROVE-ot kaptak. A reviewer a
production függvényfüggőségeket is ellenőrizte: a megőrzött helper-testek azonosak;
a többi érintett eltérés komment/formázás, opcionális AS alias vagy egy használatlan
staging deklaráció. Szemantikai javítás, történeti replay/history repair nem kell.

Kizárólag `yasrmxwjojepessivhmc` / ahely-booking-production; ACTIVE_HEALTHY,
PostgreSQL17.6.1.155. Telepítés előtt93 migration history sor; legutolsó actual
`20261014214025/admin_open_month_booking_correction`. Kizárólag az új partial SQL
alkalmazható. Production no-room-overlap exclusion constraint igazolt.

Telepítés előtti üzleti baseline (root_booking_id nélküli normalizált booking hash):

| Tábla | Sor | MD5 |
| --- | ---: | --- |
| bookings | 2328 | c2b041a6bcfd89dc6a70665f8d716727 |
| payments | 3 | b8d3b4e94b4f53ee7c676bd7603c0bf8 |
| payment_voids | 0 | d41d8cd98f00b204e9800998ecf8427e |
| monthly_settlements | 53 | 488319858282eebff7d220b1d15c1776 |
| settlement_revisions | 63 | 50004f9c7ebae1677d22ebb0a9ba5db7 |
| settlement_booking_lines | 883 | 663d28d4ba53fa39268d15ad9ca5cfc1 |
| settlement_adjustments | 0 | d41d8cd98f00b204e9800998ecf8427e |
| monthly_settlement_periods | 1 | 051d4a377a5b08c21633bcc1cb8b8032 |

## Visszaállítás és határok

Additív sémát, lemondási ledgert és befizetéseket meg kell őrizni.
Már létrejött foglaláscsoportok után a pénzügyi read model nem állítható vissza
csoportokat nem ismerő régi UI-ra egyszerű webes rollbackkel. Fizikai adat- vagy
audit-törlés tilos. A részleges lemondás saját audit/outbox eseményt hoz létre;
ez a kiadás nem aktivál új e-mail-küldést vagy banki visszafizetést.
Technikai rollback smoke különbözik a bejelentkezett felhasználói UI-UAT-tól.
