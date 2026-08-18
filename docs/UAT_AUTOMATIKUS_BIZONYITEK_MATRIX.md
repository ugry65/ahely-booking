# A-Hely foglalási rendszer – UAT automatikus bizonyíték mátrix

Kapcsolódó issue: #32

Ez a fájl azt rögzíti, hogy a manuális UAT kritikus üzleti területei mögött jelenleg milyen automatikus ellenőrzés található a repository-ban.

| Terület | Automatikus bizonyíték | Manuális UAT továbbra is kell? |
| --- | --- | --- |
| Alapséma és constraint-ek | `supabase/tests/database/000_schema_contract.sql` | igen, felhasználói működéshez |
| Egyedi foglalás | `003_create_booking_rpc.sql` | igen |
| Lemondás | `004_cancel_booking_rpc.sql` | igen |
| Módosítás | `005_update_booking_rpc.sql` | igen |
| Helyiség- és hozzáférés-admin | `006_room_access_admin.sql`, `013_room_access_admin_ui.sql` | igen |
| Névláthatóság | `007_booking_visibility.sql` | igen |
| Effektív közvetlen/csoportos jog | `008_effective_room_permissions.sql` | igen |
| Ismétlődő foglalás | `009_recurring_booking_rpc.sql`, `012_recurring_booking_ui_support.sql` | igen |
| Naptár read-model/UI támogatás | `010_calendar_ui_support.sql` | igen |
| Saját foglalások read-model | `011_my_bookings_read_model.sql` | igen |
| Havi óraszám | `014_monthly_hours_export.sql` | igen |
| CSV validáció és injection-védelem | `src/lib/monthly-hours.test.ts` | Excel/UX ellenőrzés igen |
| Egyedi foglalási űrlap validáció | `src/lib/booking-form.test.ts` | igen |
| Módosítás/lemondás űrlap validáció | `src/lib/booking-operation-form.test.ts` | igen |
| Ismétlődő űrlap validáció | `src/lib/recurring-booking-form.test.ts` | igen |
| Hozzáférés admin űrlap validáció | `src/lib/room-access-form.test.ts` | igen |
| Konkurens egyedi foglalás | `scripts/test-booking-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens foglalás-módosítás | `scripts/test-booking-mutation-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens hozzáférés-admin | `scripts/test-room-access-concurrency.sh` | nem szükséges kézzel versenyeztetni |
| Konkurens ismétlődő foglalás | `scripts/test-recurring-booking-concurrency.sh` | nem szükséges kézzel versenyeztetni |

## Jelenlegi fő bizonyítási rés

A repository erős adatbázis- és üzletilogika-tesztekkel rendelkezik, de a technikai architektúrában tervezett Playwright/E2E réteg jelenleg nem ad teljes böngészős bizonyítékot a teljes napi user journey-re. Emiatt az Issue #32 manuális staging UAT-ja kötelező.

Az UAT során talált, stabilan automatizálható regressziós esethez lehetőség szerint külön automatikus teszt készül.