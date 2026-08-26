# Claude független baseline-review – feldolgozási jegyzőkönyv

Dátum: 2026-08-26
Vizsgált baseline: `docs/CURRENT_FUNCTIONAL_BASELINE.md`
Független reviewer: Claude
Feldolgozás: ChatGPT/Work a repository tényleges kódjával és projektforrásaival összevetve.

## Aktuális összegzés

Az első Claude-review 82%-os, a második 84%-os, a harmadik 91%-os újraimplementálhatósági értékelést adott. A findingokat nem automatikusan fogadtuk el; minden lényegi pontot a repository tényleges kódjával és a projektforrásokkal ellenőriztünk.

A harmadik review után a két új P1 finding is rendezve:
- a jövőbeli pricing változások teljes idővonala látható és dokumentált;
- a legacy `admin_set_user_pricing_policy` RPC authenticated közvetlen végrehajtási joga visszavonva.

Részletes legutóbbi lezárás: `docs/CLAUDE_REVIEW_3_RESOLUTION_2026-08-26.md`.

## P0-1 – Fix user óradíj

**Státusz: CLOSED.**

Tulajdonosi döntés: a Fix óradíj megmarad aktív üzleti funkcióként.

Aktuális működés:
- az admin négy user-facing mód közül választhat: Sávos / Progresszív / Fix óradíj / Free;
- a Fix óradíj userenként, havi érvényességgel kezelhető;
- a DB pricing engine `user_price_overrides` rétegen alkalmazza;
- Free minden díjazási réteget nulláz;
- nem-Free Tréningterem Csoportos használat külön speciális díjszabály szerint számolódik;
- az admin RPC/UI elkészült;
- a kapcsolódó DB-regressziós tesztek elkészültek.

A korábbi olyan megfogalmazások, amelyek a Fix admin RPC/UI-t még production gapként jelölik, **történeti/stale állapotnak tekintendők**; az aktuális implementációs állapotot a `docs/PRICING_MODES.md`, a `docs/UAT_FUTASI_JEGYZOKONYV.md` és a jelen dokumentum írja le.

## P0-2 – Funkcionális Specifikáció v1.0

**Státusz: CLOSED.**

Az FS v1.0 formálisan **TÖRTÉNETI / SUPERSEDED**. Nem elsődleges implementációs specifikáció.

Elsődleges forrás a `docs/CURRENT_FUNCTIONAL_BASELINE.md`, az aktuális projektkontextus és az azokban hivatkozott döntési dokumentumok.

## P0-3 – UAT dokumentáció

**Státusz: CLOSED dokumentációs szinten; manuális futtatás még production kapu.**

A checklist v1.1 tartalmazza többek között:
- onboarding;
- CSV user import;
- room-group can_book/can_repeat;
- stabil calendar color/privacy;
- booking title;
- Sávos/Progresszív/Fix/Free;
- pricing effective month;
- Tréningterem default és admin egyedi díj;
- atomi booking+rate rollback;
- settlement immutabilitás;
- last-admin guard;
- payment UI parkoltatás;
- duplikálás;
- production backup/restore/monitoring kapuk.

A `UAT_FUTASI_JEGYZOKONYV.md` szinkronban van. A Fix óradíj tesztek már nem blokkoltak, hanem `NEM FUTOTT` státuszúak, mert az RPC/UI elkészült.

## P1-1 – Sorozat scope pontos szemantikája

**Státusz: PARTIALLY CLOSED / dokumentációs teendő.**

A három user-facing scope rögzített: aktuális alkalom / ettől kezdve / teljes sorozat. A pontos rekord-szintű booking/series/occurrence és Tréningterem egyedi díj öröklési szemantika még külön technológiafüggetlen dokumentálást igényel production dokumentációs lezárás előtt.

## P1-2 – Foglalási e-mail-visszaigazolás

**Státusz: CLOSED.**

Tulajdonosi döntés: nem go-live blocker és nem kötelező az első production verzióban. Kötelező az egyértelmű sikeres/sikertelen UI-visszajelzés és a sikeres foglalás azonnali megjelenése.

## P1-3 – Payment backend

**Státusz: CLOSED.**

A backend megmarad, de parkoltatott. Aktív Befizetések UI nincs, és ebben a fejlesztési fázisban nem fejlesztjük tovább. A befizetések könyvelése külön pénzügyi elszámolási folyamat része.

## P1-4 – `PRICING_MODES.md`

**Státusz: CLOSED.**

A dokumentum az aktuális kódállapotot és a Fix óradíj admin kezelést is rögzíti.

## Harmadik review – P1-NEW-1: jövőbeli pricing terv

**Státusz: CLOSED.**

A több jövőbeli díjazási változás támogatott idővonal-funkció. Egy korábbi kezdőhónap új beállítása nem törli automatikusan a későbbi, más kezdőhónapra korábban rögzített tervet.

A korábbi probléma az volt, hogy az admin UI csak a legközelebbi változást mutatta. Javítás után:
- minden jövőbeli effektív változás látható;
- külön figyelmeztetés jelzi a későbbi tervek megmaradását;
- kiválasztott usernél külön jövőbeli díjazási idővonal jelenik meg;
- a viselkedést `092_pricing_future_timeline.sql` teszt rögzíti.

## Harmadik review – P1-NEW-2: legacy pricing RPC

**Státusz: CLOSED.**

A `202608250015_harden_pricing_configuration_api.sql` visszavonja az authenticated szerepkör közvetlen EXECUTE jogát a legacy `admin_set_user_pricing_policy` függvényről. A kliens számára az egységes `admin_set_user_pricing_configuration` az egyetlen támogatott módosítási út.

## Automatikus pricing tesztek aktuális állapota

Lefedett:
- admin-only Fix beállítás;
- Fix override létrejötte;
- havi motor tényleges Fix díjszámítása;
- Free felülírás;
- Fix + Tréningterem Csoportos speciális díj;
- Fixed → Progressive;
- Progressive → Fixed;
- Fixed → Tiered;
- múltbeli hónap tiltása;
- azonos kezdőhónapú Fix terv módosítása;
- jövőbeli többváltozásos idővonal;
- DB exclusion constraint megléte az override-intervallumokra;
- legacy RPC authenticated végrehajtásának tiltása.

Külön valódi kétfolyamatos concurrency shell-teszt a pricing konfigurációra még további hardeningként elkészíthető; a DB-szintű exclusion constraint és a userenkénti advisory lock azonban jelenleg is kötelezően védi az intervallum-konzisztenciát.

## Production dokumentációs kapu – aktuális állapot

Lezárt:
1. Fix óradíj üzleti státusz;
2. régi FS dokumentumhierarchia;
3. booking e-mail go-live státusz;
4. payment backend scope;
5. friss funkciók UAT checklistje és futási jegyzőkönyve;
6. pricing future timeline és API-hardening.

Még nyitott:
1. sorozat-scope rekord-szintű, technológiafüggetlen dokumentáció;
2. legalább egy teljes dokumentált manuális staging UAT-kör;
3. production backup/off-site mentés;
4. sikeres restore-drill;
5. production monitoring/heartbeat + alert drill;
6. végső független review;
7. explicit production GO.
