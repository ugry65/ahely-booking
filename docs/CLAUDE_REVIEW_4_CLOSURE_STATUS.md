# Claude review 4 – closure státusz

Dátum: 2026-08-26
Branch: `fix/claude-review-3-closure`
PR: #91

## Review eredmény

A 4. független adversarial closure review 98%-os újraimplementálhatóságot adott, P0 és P1 finding nélkül. Három P2 teszt-/migrációtörténeti megjegyzést azonosított. A funkcionális dokumentációt READY, az UAT-ot READY TO RUN állapotúnak minősítette.

## P2-1 – series scope ownership negatív regresszió

**Státusz: CLOSED.**

A `supabase/tests/database/100_series_scope_semantics.sql` explicit negatív regressziós eseteket kapott mindkét scope RPC-re:

- más user tulajdonában lévő sorozat `update_booking_scope` művelete `P0001` hibával elutasított;
- más user tulajdonában lévő sorozat `cancel_booking_scope` művelete `P0001` hibával elutasított.

A teszt továbbra is privilegizált DB test-sessionből fut az üzleti állapot közvetlen ellenőrizhetősége miatt, de az actor a `request.jwt.claim.sub` claimből származik. A production GRANT/RLS határokat külön security tesztek fedik.

## P2-2 – redundáns legacy pricing RPC revoke migráció

**Státusz: CLOSED / dokumentált, szándékosan megtartott migrációtörténet.**

A következő két már létrejött migráció ugyanarra a legacy helperre ismétli meg az idempotens `REVOKE EXECUTE ... FROM authenticated` hardening műveletet:

- `202608250015_harden_pricing_configuration_api.sql`;
- `202608260001_harden_pricing_policy_rpc.sql`.

A második `REVOKE` funkcionálisan no-op, de biztonsági szempontból ártalmatlan. A migrációkat **nem vonjuk össze és nem töröljük visszamenőleg**, mert a már létrejött/applikált migrációs történet utólagos átírása rosszabb auditálhatóságot és környezetek közötti eltérést okozhatna, mint az idempotens redundancia. A duplikáció ezért dokumentált történeti hardening-lépésként marad meg.

Új migrációban ezt a revoke-ot további ok nélkül nem szabad újra megismételni.

## P2-3 – pricing kombinatorikus regressziók

**Státusz: CLOSED.**

A `supabase/tests/database/091_fixed_user_pricing_regressions.sql` új regressziós bizonyítékokat kapott:

- azonos folyó hónapra beállított Fix díj módosítható, és a meglévő override díja frissül;
- `Free → Fix` jövőbeli átmenet létrehozza a helyes Fix override-ot.

A teszt a folyó hónapot dinamikusan `date_trunc('month', current_date)` alapján számolja, így az új eset nem kötődik 2026 augusztusához.

## Review-jegyzőkönyvek megőrzési szabálya

A korábbi review-k lezáró dokumentumait történeti bizonyítékként kezeljük. Új review findingjait és azok lezárását új, sorszámozott closure dokumentumban kell rögzíteni; korábbi review-jegyzőkönyvet utólag csak tényszerű hibajavítás indokolhat. Ezzel megmarad, hogy az adott review pillanatában milyen állapot és döntés volt rögzítve.

## Implementációs closure bizonyíték

A 4. review azért nem tudta függetlenül igazolni a GitHub Actions állapotát, mert a reviewer környezetében GitHub API rate-limit volt. Ez nem repository-hiba.

A javítások után kötelező kapu:

1. teljes GitHub Actions DB/pgTAP tesztcsomag PASS;
2. minden concurrency teszt PASS;
3. schema lint PASS;
4. Vercel preview PASS;
5. ezután új független adversarial closure review.

## Production GO elkülönítése

A 100%-os funkcionális/újraimplementálási closure-tól továbbra is külön production GO kapu:

- dokumentált manuális staging UAT;
- production hosting/Supabase döntés;
- automatizált offsite backup;
- restore drill;
- monitoring/alert/backup-heartbeat és kontrollált riasztási drill.
