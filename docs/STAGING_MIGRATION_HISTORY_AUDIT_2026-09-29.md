# Staging migration history audit – 2026-09-29

Projekt: `fvwapntzhavhgazeflri`. Forrás: staging `supabase_migrations.schema_migrations` read-only lekérdezése (version, name, statements MD5), a PR #257 `supabase/migrations` könyvtára, a GitHub története és [#200 recovery](MIGRATION_SOURCE_OF_TRUTH_RECOVERY_200.md). Nincs history repair, adatírás vagy staging migráció alkalmazás.

## Következtetés

A 2026-09-29-i DDL előtti pillanatkép: 90 staging migration rekord, 89 helyi fájl (akkor a még nem telepített `20260929155816` fájllal együtt). 83 név szerinti egyezés; 7 távoli név helyi fájl nélkül. Az egyik különös, névként teljes helyi stemet tartalmazó sor (`20260822201228`) a `202608220020` helyi fájl jelöltje. Az azonos név önmagában nem bizonyítja a tényleges SQL azonosságát. A helyi fájl és a távoli `statements` bájtjai sokszor eltérnek (például comment/statement splitting); a táblázat az egyezést csak azonos MD5 esetén minősíti bizonyítottnak.

**A history nem rendezhető biztonságosan jelen bizonyítékkal.** A staginges adatürítő és ellenőrző lépések különálló, alkalmazott események. A hiányzó helyi migrációk egyikének eredménye ténylegesen hiányzik a sémából: a három legacy Papp-import RPC létezik, noha a `20260914120000_retire_legacy_papp_import_rpcs.sql` eltávolítaná. A teljes sémaegyezés nem igazolt. A `db push`/history repair és a feature migráció staging alkalmazása felfüggesztve.

## A hét távoli név külön vizsgálata

| Staging version | Tényleges SQL / eredet | Helyi megfelelés és bizonytalanság |
| --- | --- | --- |
| `20260821054450 repeat_booking_business_rules` | 1569 bájt, `effective_room_permissions(uuid)` függvény felülírása és grant/comment; MD5 `1edf580f529919725359368b6b526abd`. | Nincs azonos nevű fájl; későbbi repeat-permission migrációk léteznek. Nem bizonyított, melyik commit/fájl fedi le az alkalmazott állapotot. |
| `20260822201228 202608220020_recurring_series_max_span` | 1381 bájt, 366 napos trigger és függvény; MD5 `c4aa429ee05358f29e7be9b0a84b71ac`. | `202608220020_recurring_series_max_span.sql` (1398 bájt) erős név és SQL-tartalom jelölt, tárolt bájt nem azonos. Nem szabad csupán verzió alapján újrajátszani. |
| `20260924080123 preserve_legacy_training_booking_rate` | 1845 bájt, `resolve_booking_applied_rate` felülírása. | Nincs külön helyi fájl; a [#200 recovery](MIGRATION_SOURCE_OF_TRUTH_RECOVERY_200.md) a `0e075b8` és `979d703` fejlesztési történethez, majd `20260925143000` kompatibilitási migrációhoz köti. A staging 4 nem-null legacy értéket tartalmaz jelenleg, így az adatfüggő ág számít. |
| `20260927103201 staging_clear_calendar_before_multi_user_uat_final` | 1574 bájt, több booking/outbox/settlement táblából `DELETE`, trigger ideiglenes kikapcsolása; MD5 `f27592b4e40bf3a32cb259ae64ffbadc`. | Nincs helyi pár. Már alkalmazott staging-specifikus adatürítés; újrajátszása a jelenlegi adatokat törölné. Történeti rekord megőrzendő, nem jelölhető át más schema migrationre. |
| `20260927103212 verify_staging_calendar_empty_before_multi_user_uat` | 720 bájt, alkalmazáskori ürességet ellenőrző `DO` blokk; MD5 `58a32ff2c9e83875d50b8bdbf0a22e35`. | Nincs helyi pár. History-only/UAT ellenőrzés, a jelenlegi 451 booking miatt újrajátszáskor hibázna. |
| `20260927153341 allow_retroactive_pricing` | 8559 bájt, admin árazási függvények felülírása; MD5 `e1a5a2c40060adcad7896112aef11eeb`. | Nincs helyi pár; a GitHub #233 későbbi `allow_retroactive_user_hourly_rate` és `restore_future_only_global_pricing` migrációkat tartalmaz. A központi árazási rész utóbb felülírt, de a teljes hatás ekvivalenciája nincs bizonyítva. |
| `20260928091003 system_health_check_from_20260917100000` | 490 bájt, `system_health_check()` függvény és anon grant; MD5 `44a77deb144591761eefdc8a967b0769`. | `20260917100000_system_health_check.sql` (518 bájt) erős SQL-tartalom jelölt; eltérő version/név/tárolt bájt. |

## Helyi fájlok távoli verzió nélkül

| Helyi fájl | Read-only staging bizonyíték | Teendő/kockázat |
| --- | --- | --- |
| `20260914095042_generic_allbooked_customer_import.sql` | `admin_import_allbooked_customer` létezik, de a historyban nincs e version; későbbi `20260927094918` import migration van. | Részleges/későbbi felülírás lehet. Teljes lineage összevetés hiányzik; nem jelölhető vakon applied. |
| `20260914120000_retire_legacy_papp_import_rpcs.sql` | A három eltávolítandó `admin_import_papp_dalma_allbooked`, `admin_reconcile_papp_dalma_allbooked`, `admin_rollback_empty_papp_dalma_profile` RPC mind létezik (3/3). | **Bizonyított sémaeltérés**. Appliedként jelölni valótlan lenne; tényleges alkalmazását külön kompatibilitási/security ellenőrzés előzze meg. |
| `20260917100000_system_health_check.sql` | A függvény létezik, távoli `20260928091003` azonos célú SQL. | Valószínű átnevezés; a két migráció nem bájtszinten azonos. |
| `20260925143000_retire_empty_legacy_training_rate.sql` | `group_hourly_rate_huf` oszlop és 4 nem-null érték; a fájl adatfüggő ága ezen adatokat őrzi. | A history hiányzik, a jelenlegi függvény és trigger teljes megfelelése még nem bizonyított; nem jelölhető appliedként. |
| `20260929182024_monthly_settlement_publication.sql` | A vizsgálatkor még nem volt stagingen; a reconciliation után `20260929182024` valós history-verzióval alkalmaztuk. | Csak hitelesített history/sémaegyezés után alkalmazható. |

A korábbi [#200 recovery](MIGRATION_SOURCE_OF_TRUTH_RECOVERY_200.md) 42 legacy értéket rögzített szeptember 25-én; a mostani read-only ellenőrzés 4-et talált. A két külön időpont számait nem szabad összemosni. A staging jelenleg 451 bookingot, 1 settlementet, 1 revisiont tartalmaz. A stagingen adatot nem töröltünk és a production környezethez nem nyúltunk.

## Tételes 90 remote → repository jelölt

A státusz bizonyítékának szintje a táblázatban: azonos MD5 = bájtszintű SQL-egyezés; azonos név/verzió vagy hasonló tartalom = jelölt. A távoli MD5 a Postgres `md5(array_to_string(statements, ''))` értéke; több statementnél a tárolt elemeket összefűzi. Helyi SQL eltérő formátumban is ugyanazt az állapotot eredményezheti, de ezt külön schema diff nélkül nem tekintjük bizonyítottnak.

| Staging version és név | Repository jelölt | Bizonyíték szintje; remote SQL MD5 |
| --- | --- | --- |
| `202608160001` `initial_core` | `202608160001_initial_core.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `df77c89c4d9467718d91f837b87b960c` |
| `202608160002` `auth_profiles_rls` | `202608160002_auth_profiles_rls.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `cb7f064014b23436eddab6b64c40530f` |
| `202608170001` `create_booking_rpc` | `202608170001_create_booking_rpc.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `1fe9e2d0219c0f3c7e30370e62b4ea38` |
| `202608170002` `cancel_booking_rpc` | `202608170002_cancel_booking_rpc.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `646e24d8cace599c5e1b06c4065a0c12` |
| `202608170003` `unify_booking_validation` | `202608170003_unify_booking_validation.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `a400d9b3223d8a23eb9f588dfa229193` |
| `202608170004` `room_access_admin` | `202608170004_room_access_admin.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `7702dc7812e825cabbb8c7f1d4f8e14d` |
| `202608170005` `booking_visibility` | `202608170005_booking_visibility.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `7e40832659779e6eb41f2a0a29e0c9c3` |
| `202608170006` `unify_effective_room_access` | `202608170006_unify_effective_room_access.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `cdcd075f797c4efb283514b57b1434aa` |
| `202608170007` `create_recurring_booking_rpc` | `202608170007_create_recurring_booking_rpc.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `fec34aeacae6e403e0241f9e18cc3e53` |
| `202608170008` `calendar_ui_support` | `202608170008_calendar_ui_support.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `7265d4a1bf7c5dd4b095eeeb1a08ef12` |
| `202608170009` `my_bookings_read_model` | `202608170009_my_bookings_read_model.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `3daa27ae9718ec595c1eea449becd1fa` |
| `202608180001` `recurring_booking_ui_support` | `202608180001_recurring_booking_ui_support.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `2fa2c223647581c245cbcd4acdbd10c2` |
| `202608180002` `room_access_admin_ui` | `202608180002_room_access_admin_ui.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `010c11b36b05a67cb1ef5d27a444b4e7` |
| `202608180003` `monthly_hours_export` | `202608180003_monthly_hours_export.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `e298f11187bb227db6bde5094d023009` |
| `202608180004` `service_role_uat_bootstrap_grants` | `202608180004_service_role_uat_bootstrap_grants.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `e080920d7e7f34bf5612ad6558c3f50f` |
| `20260821054450` `repeat_booking_business_rules` | — | nincs név szerinti pár; remote MD5 `1edf580f529919725359368b6b526abd` |
| `20260821060345` `calendar_booking_actions` | `202608210002_calendar_booking_actions.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `4fa0f957fba70bb161987f9be90db174` |
| `20260821060408` `series_training_room_update_guard` | `202608210003_series_training_room_update_guard.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `72694bc55ca5f27477464b3a686287d5` |
| `20260821062518` `calendar_management_read_model` | `202608210004_calendar_management_read_model.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `3e3da40cdd01f09f9557d1dbb84cfc10` |
| `20260821111306` `user_billing_admin` | `202608210005_user_billing_admin.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `e3a8aa306f04113e8580092bcb13d1d9` |
| `20260821111328` `global_booking_name_visibility` | `202608210006_global_booking_name_visibility.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `282169e362c83c9ac73959faaf9e4fad` |
| `20260821111357` `required_first_login_profile` | `202608210007_required_first_login_profile.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `7cc49f825acf6101c9eb92f7b705e183` |
| `20260821111421` `admin_profile_billing_name` | `202608210008_admin_profile_billing_name.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `a4700798d518da09149f62704c921e81` |
| `20260822101208` `remove_closed_calendar_exceptions` | `202608220001_remove_closed_calendar_exceptions.sql` | SQL bájtszinten egyezik; remote MD5 `a52730c10422709fe006631d733ca14c` |
| `20260822111732` `complete_room_catalog` | `202608220002_complete_room_catalog.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `14dd04383d42e9f57e7371b193c8b74a` |
| `20260822112119` `normalize_staging_room_ids` | `202608220003_normalize_staging_room_ids.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `42f3701365fc1979774094ecc75c7591` |
| `20260822112314` `booking_title` | `202608220004_booking_title.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `2a853a4505e3f6895a6b73045e2feb9b` |
| `20260822113459` `update_own_profile_data` | `202608220005_update_own_profile_data.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `0b7219bf116b2992eb124543ae468506` |
| `20260822124120` `booking_title_compatibility` | `202608220006_booking_title_compatibility.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `f80b35a0151de35b45dd68888dbd9a00` |
| `20260822131638` `remove_ambiguous_booking_overloads` | `202608220007_remove_ambiguous_booking_overloads.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `b351e151aad5de1909d2f28020d7bbea` |
| `20260822131657` `admin_booking_audit_reports` | `202608220008_admin_booking_audit_reports.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `575f34e17cd08f9d03da5d479b082adb` |
| `20260822150301` `restore_legacy_booking_rpc_contracts` | `202608220009_restore_legacy_booking_rpc_contracts.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `b7beb2cffe5a7b2a7df0ab8262d17432` |
| `20260822150316` `preserve_legacy_booking_side_effects` | `202608220010_preserve_legacy_booking_side_effects.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `8faab86c03520bc1ab14e9c4137e5b19` |
| `20260822150327` `preserve_legacy_create_validation_contract` | `202608220011_preserve_legacy_create_validation_contract.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `6ec163375ea44e83a21c313f5d9dd456` |
| `20260822150851` `harden_update_own_profile_data_grants` | `202608220012_harden_update_own_profile_data_grants.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `a34a0afc01da07a0dfc0bf9a5f032635` |
| `20260822154855` `room_group_business_model` | `202608220013_room_group_business_model.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `17db051b539947fe77bf86a98c30de2e` |
| `20260822161722` `admin_user_role_guard` | `202608220014_admin_user_role_guard.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `d5539c1c6ee93fabe2cdaa09a5de4d11` |
| `20260822161744` `stable_user_calendar_colors` | `202608220015_stable_user_calendar_colors.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `f0b9030f2c43885a4ddab9232d8f7907` |
| `20260822174747` `user_level_repeat_permission` | `202608220016_user_level_repeat_permission.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `e718c4ba098ec79bfd74f4bcd864afa5` |
| `20260822182757` `remove_direct_repeat_promotion_trigger` | `202608220017_remove_direct_repeat_promotion_trigger.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `bc00e201185a40d3879fa9a90751942b` |
| `20260822191437` `profile_repeat_select_grant` | `202608220018_profile_repeat_select_grant.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `64412f4e77c887898693f757f9be23df` |
| `20260822200005` `admin_advance_booking_limits` | `202608220019_admin_advance_booking_limits.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `37b4d5ab0715e19429523eb43982975d` |
| `20260822201228` `202608220020_recurring_series_max_span` | `202608220020_recurring_series_max_span.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `c4aa429ee05358f29e7be9b0a84b71ac` |
| `202608250001` `user_pricing_policies` | `202608250001_user_pricing_policies.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `1a05ce94eff0f7890e06c433014638d6` |
| `202608250002` `monthly_pricing_engine` | `202608250002_monthly_pricing_engine.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `33e1adbc68d0252366eb0ee57dd18792` |
| `202608250003` `admin_monthly_pricing_summary` | `202608250003_admin_monthly_pricing_summary.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `95a1f2152b951774e38eb929866dcfbd` |
| `202608250004` `settlement_snapshot` | `202608250004_settlement_snapshot.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `a6a8965a2a09c48942a5819c822bf23d` |
| `202608250005` `admin_settlement_status` | `202608250005_admin_settlement_status.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `623972a75ab19119fc4fb1b1894c3ab0` |
| `202608250006` `training_group_booking_rate` | `202608250006_training_group_booking_rate.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `5294bf9aaa845b18f9c65c7d54087e58` |
| `202608250007` `training_group_series_rate` | `202608250007_training_group_series_rate.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `52018c70836a6ee09d62f236e9c519be` |
| `202608250008` `payment_management` | `202608250008_payment_management.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `c35170e6990844139a2d0bb563cd231f` |
| `202608250009` `payment_history` | `202608250009_payment_history.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `6b3b53a4a661b28b5ac71ee273c534d8` |
| `202608250010` `harden_payment_idempotency` | `202608250010_harden_payment_idempotency.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `4ea9f070f1192d0f8cf5304bb475b718` |
| `202608250011` `monthly_booking_detail_title` | `202608250011_monthly_booking_detail_title.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `2f476e0b3fa578e126269e78e07424b3` |
| `202608250012` `atomic_training_group_rate_creation` | `202608250012_atomic_training_group_rate_creation.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `e7a824cfded94bb226ca73225b34b68b` |
| `202608250013` `security_hardening_internal_helpers` | `202608250013_security_hardening_internal_helpers.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `9f0dc9010acbeb0b3fa6176f7de2bab1` |
| `202608250014` `fixed_user_pricing_admin` | `202608250014_fixed_user_pricing_admin.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `70df4d4b355924e695a502ca9c92d075` |
| `202608250015` `harden_pricing_configuration_api` | `202608250015_harden_pricing_configuration_api.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `4b03529a3ae828b114db8dc05c7cfb15` |
| `202608260001` `harden_pricing_policy_rpc` | `202608260001_harden_pricing_policy_rpc.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `89f1bd96cd5edba35693a0d6452937e5` |
| `202608260002` `harden_settlement_booking_line_immutability` | `202608260002_harden_settlement_booking_line_immutability.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `044dfca452c0859c062d678826b7b732` |
| `20260826205749` `protect_closed_settlement_line_inserts` | `20260826205749_protect_closed_settlement_line_inserts.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `3cf8d1c5b26896a0e0341ebae4799b8b` |
| `20260829145720` `allow_past_booking_creation` | `20260829145720_allow_past_booking_creation.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `95594ea89bb71f5fcd506e1e81042534` |
| `20260830183000` `booking_update_cutoff_guard` | `20260830183000_booking_update_cutoff_guard.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `665d1c42c0ee92a012609fdf463cc4f2` |
| `202609030001` `booking_email_outbox` | `202609030001_booking_email_outbox.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `b477745326d5be96f7d273fa61110aad` |
| `202609030002` `enqueue_booking_emails_from_audit` | `202609030002_enqueue_booking_emails_from_audit.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `7923811b4d7ba3c71121435a4df3acfd` |
| `20260903185410` `booking_email_delivery_monitor` | `20260903185410_booking_email_delivery_monitor.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `acbd90ce36ce0549f9c819eb0e34cfad` |
| `202609040001` `first_login_password_change` | `202609040001_first_login_password_change.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `5a0eb7ebaf341c03ba743d645e1088cd` |
| `202609050001` `admin_temporary_password` | `202609050001_admin_temporary_password.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `7fb6fc4f16ffcc4e0f997c6346148dd4` |
| `202609050002` `precise_password_change_audit` | `202609050002_precise_password_change_audit.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `464250f056a672745abf1433f4d12586` |
| `20260909182529` `allbooked_staging_import` | `20260909182529_allbooked_staging_import.sql` | azonos verzió/név, SQL eltérő tárolási formátum; remote MD5 `ee9d3a44c240115a84aa7eb35e545316` |
| `20260921193000` `booking_email_bridge_safe_warning` | `20260921193000_booking_email_bridge_safe_warning.sql` | SQL bájtszinten egyezik; remote MD5 `6d451250c853a601627fc3730bff4d94` |
| `20260923171023` `admin_pricing_and_booking_rate_override` | `20260922160000_admin_pricing_and_booking_rate_override.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `c2c9f82660585c5ca342202974129b81` |
| `20260924080123` `preserve_legacy_training_booking_rate` | — | nincs név szerinti pár; remote MD5 `e1c9ea432c4782233cc1acd4cff2dcd8` |
| `20260924181855` `allbooked_preserve_booking_notes` | `20260924183000_allbooked_preserve_booking_notes.sql` | SQL bájtszinten egyezik; remote MD5 `d22a1cffb9d950531f259c4b528a2f23` |
| `20260925095053` `booking_email_recurring_summary` | `20260925100000_booking_email_recurring_summary.sql` | SQL bájtszinten egyezik; remote MD5 `f2c2e7bc4bc19d79d8d1ebdf18fcf342` |
| `20260926093250` `move_btree_gist_out_of_public` | `20260926103000_move_btree_gist_out_of_public.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `ae843fe2de9974a9df7fb2de90c8664d` |
| `20260927094918` `multi_customer_allbooked_batch` | `20260927120000_multi_customer_allbooked_batch.sql` | SQL bájtszinten egyezik; remote MD5 `9fa24a42bb4f6299a337b5177cdbeec1` |
| `20260927103201` `staging_clear_calendar_before_multi_user_uat_final` | — | nincs név szerinti pár; remote MD5 `f27592b4e40bf3a32cb259ae64ffbadc` |
| `20260927103212` `verify_staging_calendar_empty_before_multi_user_uat` | — | nincs név szerinti pár; remote MD5 `58a32ff2c9e83875d50b8bdbf0a22e35` |
| `20260927125819` `harden_allbooked_auth_compensation` | `20260927124500_harden_allbooked_auth_compensation.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `2f1af35d991b9df723293a3b17408950` |
| `20260927153341` `allow_retroactive_pricing` | — | nincs név szerinti pár; remote MD5 `e1a5a2c40060adcad7896112aef11eeb` |
| `20260927162837` `admin_user_email_change` | `20260927190000_admin_user_email_change.sql` | SQL bájtszinten egyezik; remote MD5 `d3904b6342201a5ad54a8b738d8ad4e4` |
| `20260927162955` `monthly_summary_pricing_breakdown` | `20260927193000_monthly_summary_pricing_breakdown.sql` | SQL bájtszinten egyezik; remote MD5 `cdc9e59b35107f0e2a9d6f8d290335cd` |
| `20260927163032` `allow_retroactive_user_hourly_rate` | `20260927194000_allow_retroactive_user_hourly_rate.sql` | SQL bájtszinten egyezik; remote MD5 `d53f99e9bf3f379548789a5621e4658a` |
| `20260927171944` `email_finalize_accept_auth_profile_sync` | `20260927201500_email_finalize_accept_auth_profile_sync.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `26f3e35c63d1efa700550ef1613d418c` |
| `20260927180020` `email_change_explicit_actor` | `20260927210000_email_change_explicit_actor.sql` | SQL bájtszinten egyezik; remote MD5 `6b4730449228bc70cca0c84379efd910` |
| `20260927182632` `restore_future_only_global_pricing` | `20260927213000_restore_future_only_global_pricing.sql` | SQL bájtszinten egyezik; remote MD5 `896059c02f1da934cb31f02aeb31c76d` |
| `20260928091003` `system_health_check_from_20260917100000` | `20260917100000_system_health_check.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `44a77deb144591761eefdc8a967b0769` |
| `20260928143742` `user_calendar_color_self_service` | `20260928162000_user_calendar_color_self_service.sql` | SQL bájtszinten egyezik; remote MD5 `90e3fa456566007e6e4cbec811c327a9` |
| `20260928144805` `allow_own_calendar_color_read` | `20260928165000_allow_own_calendar_color_read.sql` | eltérő verzió, SQL külön ellenőrzendő; remote MD5 `d077777cdd2ec6d558af7d992c64f9b3` |

## Feloldáshoz hiányzó bizonyíték

1. A staging schema objektumszintű összevetése a repository migrációk tiszta, izolált rebuildjével, külön a legacy Training-rate és AllBooked import RPC-kre, árazásra és permission függvényekre.
2. A hét rendhagyó távoli SQL teljes, megőrzött forrásának Git provenance-e és a két staging UAT esemény history-megőrzési stratégiája. Az adatürítő SQL-t **tilos** újrajátszani.
3. A hiányzó helyi migration verziók tételes applied-vs-unapplied bizonyítása. History repair csak akkor jelölhet alkalmazottnak fájlt, ha hatását már bizonyítottan hordozza a séma; egyébként külön, előre mutató migration kell.

A history hibás átcímkézése kihagyná a hiányzó DDL-t, vagy destruktív UAT SQL újrajátszásához/rossz sorrendű díjszámításhoz vezethet. Ezért a staging DB deployment és UAT jelenleg blokkolt.

A fenti 90/89 számok történeti pre-reconciliation állapotot jelölnek. A stagingen az új forward reconciliation `20260929181222`, majd a PR #257 feature `20260929182024` ténylegesen lefutott; a history 92 bejegyzés. A `20260914095042` és `20260914120000` nincs appliednek jelölve. A védett dry-run és a részletes bizonyíték a [PR #258 reconciliation dokumentációban](https://github.com/ugry65/ahely-booking/blob/chore/staging-schema-reconciliation/docs/STAGING_SCHEMA_RECONCILIATION_2026-09-29.md) található.
