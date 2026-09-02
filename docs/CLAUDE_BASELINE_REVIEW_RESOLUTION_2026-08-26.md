# Claude független baseline-review – feldolgozási jegyzőkönyv

Dátum: 2026-08-26
Aktuális kanonikus baseline: `docs/CURRENT_FUNCTIONAL_BASELINE.md` v1.2
Független reviewer: Claude
Feldolgozás: ChatGPT/Work a repository tényleges kódjával, tesztjeivel és projektforrásaival összevetve.

## Aktuális összegzés

Az első Claude-review 82%-os, a második 84%-os, a harmadik 91%-os újraimplementálhatósági értékelést adott. A findingokat nem automatikusan fogadtuk el: minden lényegi pontot a tényleges kóddal és üzleti döntésekkel ellenőriztünk.

A harmadik review utáni javítási körben:
- elkészült és hardenelve lett a Fix óradíj teljes admin RPC/UI útja;
- a legacy pricing helper authenticated közvetlen végrehajtási joga megszűnt;
- minden jövőbeli pricing-változás látható, a későbbi tervek megmaradásának szemantikája dokumentált és tesztelt;
- a kanonikus baseline v1.2-re frissült;
- az ismétlődő sorozatok occurrence/following/series szemantikája külön technológiafüggetlen specifikációt kapott (`docs/SERIES_SCOPE_SEMANTICS.md`), és a baseline-ba is beolvadt;
- a UAT checklist, futási jegyzőkönyv és automatikus bizonyíték-mátrix szinkronizálva lett;
- célzott pricing és series-scope regressziós tesztek készültek.

## Korábbi P0 findingok

### P0-1 – Fix user óradíj
**Státusz: CLOSED.**

A Fix óradíj aktív, megtartott üzleti feature. Adminból mód, Ft/óra és effective month kezelhető. A backend egységes, auditált konfigurációs RPC-t használ. Free minden más pricing réteget felülír; nem-Free Tréningterem Csoportos saját speciális díjon számolódik.

### P0-2 – Funkcionális Specifikáció v1.0
**Státusz: CLOSED.**

Az FS v1.0 TÖRTÉNETI / SUPERSEDED. A `CURRENT_FUNCTIONAL_BASELINE.md` a kanonikus funkcionális forrás.

### P0-3 – UAT dokumentáció
**Státusz: CLOSED dokumentációs szinten.**

A checklist v1.2, a futási jegyzőkönyv és az automatikus bizonyíték-mátrix az aktuális baseline-nal szinkronban van. A manuális staging UAT tényleges lefuttatása továbbra is production readiness kapu, nem dokumentációs hiány.

## Korábbi P1 findingok

### P1-1 – Sorozat-scope pontos szemantikája
**Státusz: CLOSED.**

Kanonikus részletspecifikáció: `docs/SERIES_SCOPE_SEMANTICS.md`.

Rögzítve és a baseline v1.2-be beolvasztva:
- occurrence/following/series pontos célhalmaz;
- csak aktív jövőbeli bookingok módosulnak;
- update időeltolás/duration/room/use_type/note szemantika;
- teljes célhalmaz elővalidálása és atomi rollback;
- optimistic concurrency;
- cancel cutoff teljes-scope rollback;
- idempotencia és audit;
- booking_title megőrzés;
- Tréningterem booking-specifikus group rate megőrzés/nullázás/default 5000 szabály.

Automatikus bizonyíték: `099_calendar_booking_management.sql` és `100_series_scope_semantics.sql`.

### P1-2 – Foglalási e-mail-visszaigazolás
**Státusz: CLOSED.**

Nem go-live blocker. A sikeres/sikertelen UI-visszajelzés és az azonnali naptár-megjelenés kötelező.

### P1-3 – Payment backend
**Státusz: CLOSED.**

Backend parkoltatott/befagyasztott, aktív payment UI nincs.

### P1-4 – `PRICING_MODES.md`
**Státusz: CLOSED.**

A dokumentum az aktuális 4 üzleti módot, precedenciát, jövőbeli idővonalat és API-határt írja le.

## Harmadik review – P1-NEW-1: jövőbeli pricing terv

**Státusz: CLOSED.**

A rendszer tudatosan támogat több jövőbeli pricing-változást. Egy korábbi kezdőhónap módosítása nem törli csendben a későbbi tervet. Az admin minden jövőbeli effektív változást időrendben lát, és külön UI-figyelmeztetést kap. Automatizált bizonyíték: `092_pricing_future_timeline.sql`.

## Harmadik review – P1-NEW-2: legacy pricing RPC

**Státusz: CLOSED.**

A legacy `admin_set_user_pricing_policy` authenticated EXECUTE joga visszavonva. Kliensoldali módosítás kizárólag az egységes `admin_set_user_pricing_configuration` útvonalon történhet. Regressziós bizonyíték: `091_fixed_user_pricing_hardening.sql`, `091_fixed_user_pricing_regressions.sql`.

## Automatikus bizonyíték – aktuális fő területek

Pricing:
- Sávos / Progresszív / Free;
- Fix admin-only beállítás és audit;
- Fix havi számítás;
- Free precedencia;
- Fix + Tréningterem speciális pricing;
- Fixed→Progresszív és Fixed→Sávos;
- múltbeli hónap tiltása;
- jövőbeli pricing-idővonal;
- legacy helper API lezárása.

Sorozat-scope:
- following update;
- occurrence és teljes-series update;
- occurrence/following/series cancellation célhalmaz;
- cutoff atomi rollback;
- booking_title megőrzés;
- Tréningterem 7500 rate megőrzése, speciális státusz elhagyásakor nullázás, visszalépéskor default 5000.

Teljes referencia: `docs/UAT_AUTOMATIKUS_BIZONYITEK_MATRIX.md`.

## Dokumentációs closure állapot

A negyedik független Claude-review előtt dokumentációs szinten lezárt:
1. négy pricing mód és precedencia;
2. Fix admin RPC/UI és API-hardening;
3. jövőbeli pricing-idővonal;
4. régi FS hierarchia;
5. booking e-mail státusz;
6. payment scope;
7. UAT checklist/futási napló/bizonyíték-mátrix;
8. occurrence/following/series teljes szemantika;
9. kanonikus baseline v1.2 és projektkontextus szinkronja.

A következő review feladata újra teljes, adversarial closure audit. 100% csak akkor fogadható el, ha nincs unresolved P0/P1/P2 dokumentációs vagy implementációs finding a jelenlegi funkcionális baseline scope-jában.

## Külön production readiness kapuk

A dokumentációs/újraimplementálhatósági closure-től elkülönülően production GO előtt még tényleges bizonyíték szükséges:
- teljes dokumentált manuális staging UAT;
- production backup automatizálás/off-site példány;
- sikeres restore-drill;
- production monitoring/heartbeat + alert/recovery drill;
- végső kritikus független review;
- production konfiguráció/deploy/rollback ellenőrzés;
- explicit üzleti GO.

Ezek nyitott production kapuk, de ha pontosan dokumentáltak, önmagukban nem jelentenek hiányos újraimplementálási specifikációt.
