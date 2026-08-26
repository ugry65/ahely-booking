# A-Hely foglalási rendszer – UAT automatikus bizonyíték mátrix

Verzió: 1.2
Dátum: 2026-08-26
Kapcsolódó issue-k: #32, #82
Kanonikus baseline: `docs/CURRENT_FUNCTIONAL_BASELINE.md` v1.2

Ez a fájl azt rögzíti, hogy a manuális UAT kritikus üzleti területei mögött milyen automatikus ellenőrzés található a repository-ban. Az automatikus bizonyíték nem helyettesíti a manuális staging UAT-t ott, ahol a böngészős/user-facing működést is igazolni kell.

| Terület | Automatikus bizonyíték | Manuális UAT továbbra is kell? |
| --- | --- | --- |
| Alapséma és constraint-ek | `supabase/tests/database/000_schema_contract.sql` | igen, felhasználói működéshez |
| Egyedi foglalás | `003_create_booking_rpc.sql` | igen |
| Lemondás | `004_cancel_booking_rpc.sql` | igen |
| Módosítás | `005_update_booking_rpc.sql` | igen |
| Helyiség- és hozzáférés-admin | `006_room_access_admin.sql`, `013_room_access_admin_ui.sql` | igen |
| Névláthatóság | `007_booking_visibility.sql` | igen |
| Effektív közvetlen/csoportos jog | `008_effective_room_permissions.sql`, `026_room_group_business_model.sql`, `029_user_level_repeat_permission.sql` | igen |
| Ismétlődő foglalás létrehozás | `009_recurring_booking_rpc.sql`, `012_recurring_booking_ui_support.sql`, `030_recurring_advance_limits.sql` | igen |
| Ismétlődő sorozat occurrence/following/series update/cancel | `099_calendar_booking_management.sql`, `100_series_scope_semantics.sql` | igen, UX és scope-választás |
| Sorozat-scope booking title és Tréningterem csoportdíj megőrzése/nullázása/defaultja | `100_series_scope_semantics.sql` | igen |
| Naptár read-model/UI támogatás | `010_calendar_ui_support.sql` | igen |
| Saját foglalások read-model | `011_my_bookings_read_model.sql` | igen |
| Onboarding | `016_user_onboarding.sql` | igen |
| Foglalás címe | `019_booking_title.sql`, `020_booking_title_visibility.sql`, `087_monthly_booking_detail_title.sql` | igen |
| Utolsó admin védelem | `027_admin_user_role_guard.sql` + `scripts/test-last-admin-concurrency.sh` | igen |
| Stabil calendar color/privacy | `028_stable_user_calendar_colors.sql` + concurrency test | igen |
| Havi óraszám / export backend | `014_monthly_hours_export.sql` | igen |
| Sávos/progresszív/Free havi pricing | `028_monthly_pricing_engine.sql`, `082_user_pricing_policies.sql` | igen |
| Fix óradíj admin-only, audit, havi számítás | `090_fixed_user_pricing_admin.sql` | igen |
| Fix pricing API hardening, Fixed→Progresszív/Sávos, múltbeli tiltás, Tréningterem precedencia | `091_fixed_user_pricing_hardening.sql`, `091_fixed_user_pricing_regressions.sql` | igen |
| Jövőbeli pricing-idővonal / későbbi terv megmaradása | `092_pricing_future_timeline.sql` | igen |
| Tréningterem default 5000 és bookingonkénti override | `085_training_group_booking_rate.sql` | igen |
| Atomi Tréningterem booking/sorozat + egyedi díj | `088_atomic_training_group_rate_creation.sql` | igen |
| Settlement snapshot/immutabilitás | `084_settlement_snapshot.sql` | igen |
| Security helper hardening | `089_security_hardening_internal_helpers.sql` | nem user-facing; review szükséges |
| CSV validáció és injection-védelem | `src/lib/monthly-hours.test.ts` | Excel/UX ellenőrzés igen |
| Egyedi foglalási űrlap validáció | `src/lib/booking-form.test.ts` | igen |
| Módosítás/lemondás űrlap validáció | `src/lib/booking-operation-form.test.ts` | igen |
| Ismétlődő űrlap validáció | `src/lib/recurring-booking-form.test.ts` | igen |
| Hozzáférés admin űrlap validáció | `src/lib/room-access-form.test.ts` | igen |
| Konkurens egyedi foglalás | `scripts/test-booking-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens foglalás-módosítás | `scripts/test-booking-mutation-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens hozzáférés-admin | `scripts/test-room-access-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens ismétlődő foglalás | `scripts/test-recurring-booking-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Repeat permission kompatibilitási konkurencia | kapcsolódó CI shell test | nem |

## CI bizonyítási elv

A Database tests workflow egy tiszta lokális adatbázist épít újra a migrációkból, futtatja a teljes pgTAP készletet, a konkurenciateszteket és a schema lintet. Egy release-kandidatát csak az ugyanazon commiton zöld teljes CI mellett lehet elfogadni.

## Jelenlegi fő bizonyítási rés

A repository erős adatbázis- és üzletilogika-tesztekkel rendelkezik, de a technikai architektúrában tervezett teljes Playwright/E2E réteg jelenleg nem ad teljes böngészős bizonyítékot minden napi user journey-re. Emiatt a `docs/FUNKCIONALIS_UAT_CHECKLIST.md` szerinti manuális staging UAT továbbra is kötelező production kapu.

A production infrastruktúra (backup, tényleges restore, monitoring/alert) külön kontrollált drill-lel bizonyítandó; ezek nem helyettesíthetők pusztán unit/DB teszttel.
