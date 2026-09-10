# A-Hely foglalási rendszer – UAT automatikus bizonyíték mátrix

Verzió: 1.3
Dátum: 2026-08-30
Kapcsolódó issue-k: #32, #82
Kanonikus baseline: `docs/CURRENT_FUNCTIONAL_BASELINE.md` v1.2

Ez a fájl azt rögzíti, hogy a manuális UAT kritikus üzleti területei mögött milyen automatikus ellenőrzés található a repository-ban. Az automatikus bizonyíték nem helyettesíti a manuális staging UAT-t ott, ahol a böngészős/user-facing működést is igazolni kell.

A harmadik oszlop a bizonyíték **típusát**, nem új tesztfeladatot jelöl. A már elfogadott kézi és modul-UAT eredmények a [futási jegyzőkönyvben](UAT_FUTASI_JEGYZOKONYV.md) és a [tételes auditban](UAT_BIZONYITEK_EGYEZTETES_2026-08-30.md) érvényesek. Egy régi „igen” nem írhatja felül a meglévő PASS-t. A rövid SQL-fájlnevek a `supabase/tests/database/` könyvtárban értendők.

| Terület | Automatikus bizonyíték | Böngészős bizonyíték szerepe (nem újrateszt-lista) |
| --- | --- | --- |
| Alapséma és constraint-ek | `supabase/tests/database/000_schema_contract.sql` | UI-bizonyíték külön kezelendő, felhasználói működéshez; korábbi eredmény a jegyzőkönyvben |
| Egyedi foglalás | `003_create_booking_rpc.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Lemondás | `004_cancel_booking_rpc.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Módosítás | `005_update_booking_rpc.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Helyiség- és hozzáférés-admin | `006_room_access_admin.sql`, `013_room_access_admin_ui.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Névláthatóság | `007_booking_visibility.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Effektív közvetlen/csoportos jog | `008_effective_room_permissions.sql`, `026_room_group_business_model.sql`, `029_user_level_repeat_permission.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Ismétlődő foglalás létrehozás | `009_recurring_booking_rpc.sql`, `012_recurring_booking_ui_support.sql`, `030_recurring_advance_limits.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Ismétlődő sorozat occurrence/following/series update/cancel | `099_calendar_booking_management.sql`, `100_series_scope_semantics.sql` | UI-bizonyíték külön kezelendő, UX és scope-választás; korábbi eredmény a jegyzőkönyvben |
| Sorozat-scope booking title és Tréningterem csoportdíj megőrzése/nullázása/defaultja | `100_series_scope_semantics.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Naptár read-model/UI támogatás | `010_calendar_ui_support.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Saját foglalások read-model | `011_my_bookings_read_model.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Onboarding | `016_user_onboarding.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Foglalás címe | `019_booking_title.sql`, `020_booking_title_visibility.sql`, `087_monthly_booking_detail_title.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Utolsó admin védelem | `027_admin_user_role_guard.sql` + `scripts/test-admin-role-guard-concurrency.sh` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Stabil calendar color/privacy | `028_stable_user_calendar_colors.sql` + `scripts/test-calendar-color-concurrency.sh` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Havi óraszám / export backend | `014_monthly_hours_export.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Sávos/progresszív/Free havi pricing | `028_monthly_pricing_engine.sql`, `082_user_pricing_policies.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Fix óradíj admin-only, audit, havi számítás | `090_fixed_user_pricing_admin.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Fix pricing API hardening, Fixed→Progresszív/Sávos, múltbeli tiltás, Tréningterem precedencia | `091_fixed_user_pricing_hardening.sql`, `091_fixed_user_pricing_regressions.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Jövőbeli pricing-idővonal / későbbi terv megmaradása | `092_pricing_future_timeline.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Tréningterem default 5000 és bookingonkénti override | `085_training_group_booking_rate.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Atomi Tréningterem booking/sorozat + egyedi díj | `088_atomic_training_group_rate_creation.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Settlement snapshot/immutabilitás | `084_settlement_snapshot.sql` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Security helper hardening | `089_security_hardening_internal_helpers.sql` | nem user-facing; review szükséges |
| CSV validáció és injection-védelem | `src/lib/monthly-hours.test.ts` | Excel/UX ellenőrzés igen |
| Egyedi foglalási űrlap validáció | `src/lib/booking-form.test.ts` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Módosítás/lemondás űrlap validáció | `src/lib/booking-operation-form.test.ts` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Ismétlődő űrlap validáció | `src/lib/recurring-booking-form.test.ts` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Ismétlődő sorozat lezárási módjai a normál foglalási modalban | `src/app/(protected)/foglalasok/recurring-end-fields.test.tsx` | UI-bizonyíték külön kezelendő, a módváltás és a teljes user journey miatt; korábbi eredmény a jegyzőkönyvben |
| Hozzáférés admin űrlap validáció | `src/lib/room-access-form.test.ts` | UI-bizonyíték külön kezelendő; korábbi eredmény a jegyzőkönyvben |
| Konkurens egyedi foglalás | `scripts/test-booking-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens foglalás-módosítás | `scripts/test-booking-mutation-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens hozzáférés-admin | `scripts/test-room-access-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens ismétlődő foglalás | `scripts/test-recurring-booking-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Repeat permission kompatibilitási konkurencia | `scripts/test-repeat-permission-concurrency.sh` | nem |

## CI bizonyítási elv

A Database tests workflow egy tiszta lokális adatbázist épít újra a migrációkból, futtatja a teljes pgTAP készletet, a konkurenciateszteket és a schema lintet. Egy release-kandidatát csak az ugyanazon commiton zöld teljes CI mellett lehet elfogadni.

## Ellenőrzött aktuális CI és tételes lezárások

Ellenőrzött dokumentációs head: `6816c1b7260e52c12811a6ec295154c67ca5990c`. [Application #441](https://github.com/ugry65/ahely-booking/actions/runs/33316833260): 18 fájl / 86 teszt, typecheck/build PASS. [Database #411](https://github.com/ugry65/ahely-booking/actions/runs/33316833237): 46 SQL-fájl / 615 pgTAP, 7 konkurencialépés és lint PASS. A futások logját és a megnevezett assertionök forrását ellenőriztük; nem csak a tesztfájl nevét.

- BOOK-11: `003_create_booking_rpc.sql` azonos kulcs/azonos payload visszaadását; `scripts/test-booking-concurrency.sh` két párhuzamos azonos kulcsú kérés sikerét és pontosan 1 booking/audit/outbox rekordot ellenőriz. Megfelelő automatikus PASS; nem kézi race.
- EDIT-05: `scripts/test-booking-mutation-concurrency.sh` ugyanabból a verzióból indított két update közül pontosan egy sikert, a vesztesnél stale-version hibát és 1 audit/outbox/ledger eredményt vár. Megfelelő automatikus PASS.
- ADMIN-07: `029_user_level_repeat_permission.sql`, `031_repeat_legacy_rpc_contract.sql` és a repeat concurrency a PR #77-ben elfogadott **profil-szintű** repeat modellt védi; nem a régi közvetlen per-room jogot.
- A zöld automatikus csomag nem bizonyítja a teljes böngészős UX-et és nem jelent új kézi UAT-futtatást.

## Bizonyítékhatárok – nem bizonyított alkalmazáshibák

- EDIT-04: a vizsgált `005_update_booking_rpc.sql` 19 assertionje között nincs külön 24 órán belüli saját módosítás elutasítására azonosított assertion. Az update egyéb validációja és a cancel cutoff nem ennek a célzott bizonyítéka.
- REC-13: a `099_calendar_booking_management.sql` (16 assertion) és `100_series_scope_semantics.sql` (24 assertion) normál scope-műveleteket és több jogosultsági/pénzügyi kontrollt fed le. A 100-as cutoff miatti **cancel** rollback és a 009-es sorozatlétrehozási `abort_all` nem ugyanaz, mint egy ütköző scope-**update** összes targetjének visszagörgetése. E két scope-tesztben erre külön assertiont nem azonosítottunk.
- Ez korlátozott bizonyítékmegállapítás, nem a teljes rendszer tesztlefedetlenségének vagy hibás implementációjának állítása. Kód/teszt kiterjesztést ez a dokumentációs commit nem végez.

## Jelenlegi fő bizonyítási rés

A repository erős adatbázis- és üzletilogika-tesztekkel rendelkezik, de a technikai architektúrában tervezett teljes Playwright/E2E réteg jelenleg nem ad teljes böngészős bizonyítékot minden napi user journey-re. A checklist szerinti megfelelő felhasználói elfogadás production kapu marad, de a már meglévő manuális/modul-UAT bizonyítékot megőrizzük. A hiányzó teljes E2E-automatizálás nem teszi semmissé a történeti kézi elfogadást, és nem rendel el teljes újratesztelést.

A production infrastruktúra (backup, tényleges restore, monitoring/alert) külön kontrollált drill-lel bizonyítandó; ezek nem helyettesíthetők pusztán unit/DB teszttel.
