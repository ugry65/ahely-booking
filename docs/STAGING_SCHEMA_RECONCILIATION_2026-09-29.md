# Staging schema reconciliation – read-only megállási pont (2026-09-29)

Állapot: **blokkolt, staging írás nem történt**. A havi elszámolás PR #257 migrationje nem része ennek a referencia-sémának és stagingre nem került.

## Módszer és bizonyíték

- Repository baseline: `main` `4ce6f60f280f10a6a23569059ce1ea63c5b8d9d5`, a PR #258 kizárólag read-only leltárkészítő SQL-t és izolált CI workflow-t ad hozzá.
- [Izolált CI-futás](https://github.com/ugry65/ahely-booking/actions/runs/36605545208): Supabase CLI 2.114.0, helyi PostgreSQL 15, `supabase db start` és `supabase db reset --no-seed`; a repository migrációiból üres, elkülönült referencia állt fel. A [séma-leltár artifact](https://github.com/ugry65/ahely-booking/actions/runs/36605545208/artifacts/11051241270) 947 objektumsort tartalmaz, a futás PASS.
- A staging `fvwapntzhavhgazeflri` PostgreSQL 17 adatbázist ugyanazzal a [read-only leltár SQL-lel](../scripts/schema-inventory.sql) kérdeztük le: 956 objektumsor. A leltár táblát, oszlopot/típust/defaultot, constraintet, indexet, RLS-t, policy-t, függvénydefiníciót és végrehajtási jogot, triggert, enumot és effektív tábla-jogot tartalmaz. Kizárólag a `public` alkalmazásséma szerepel, extension-owned objektumok nélkül. Személyes vagy soradat nem került artifactba.
- 947/956 azonosítót és definíciót hasonlítottunk össze. A 34 eltérő tábla-grant kizárólag a PostgreSQL 17 `MAINTAIN` (`m`) ACL-bitje miatt különbözik a PG15 referenciától; az anon/authenticated/service_role SELECT/INSERT/UPDATE/DELETE effektív jogok megegyeznek. A 12 azonos nevű függvény MD5-eltérése komment/whitespace, illetve egy nem hivatkozott `AS lock_key` alias; a normalizált kód és a függvény-grantek megegyeznek. A szemantikai azonosság további célzott teszttel erősíthető, de e különbségek nem magyarázzák az alábbi hiányokat.

## Objektumszintű eredmény

| Kategória | Referencia ↔ staging |
| --- | --- |
| Táblák/view-k/sequence-ek, indexek, RLS, policy-k | Azonos objektumok és definíciók. |
| Oszlop/constraint/trigger | Stagingen többlet: `bookings.group_hourly_rate_huf`, ellenőrző constraint, `bookings_training_group_rate_default`. A [#200 recovery](MIGRATION_SOURCE_OF_TRUTH_RECOVERY_200.md) adatfüggő kompatibilitási ágából ered; jelenleg 4 történeti nem-null díjat őriz, ezért eltávolítani tilos. |
| Enum | Referenciában `booking_status = active,cancelled,voided`; stagingen csak `active,cancelled`. A `voided` értéket kizárólag a helyi `20260914095042` migration adja hozzá. |
| Referenciában meglévő, stagingen hiányzó RPC | `admin_void_papp_dalma_test_import(uuid,text,uuid)`, `admin_rollback_empty_allbooked_profile(uuid,uuid,text)`; mindkettő a helyi `20260914095042` része. Előbbi egy 21 bookingos próbaimport státuszát és profilját változtathatja meg explicit, guardolt hívással; az alkalmazásban production-célhoz kötött API-route még hivatkozik rá. Utóbbi üres profil kompenzáló eltávolítása. |
| Staging többlet RPC | A három régi Papp-import RPC és két legacy Training-rate RPC. Az utóbbi két RPC a 4 nem-null történeti díj miatt szükséges kompatibilitási ág. |

## Hét rendhagyó remote migration besorolása

| Remote version | Osztály | Bizonyíték |
| --- | --- | --- |
| `20260821054450 repeat_booking_business_rules` | **D** – később felülírt | A tárolt SQL az `effective_room_permissions(uuid)` definícióját cserélte; a helyi `202608220013` és `202608220016` ismét cseréli. A jelenlegi függvénydefiníció és grant a két leltárban azonos. |
| `20260822201228 202608220020_recurring_series_max_span` | **A** – ekvivalens helyi migration | Helyi `202608220020` ugyanazt a 366 napos trigger/funkciót hozza létre, a jelenlegi definíció és trigger egyezik; tárolt SQL formázása eltér. |
| `20260924080123 preserve_legacy_training_booking_rate` | **B** – szükséges történeti kompatibilitás | A tárolt SQL a díj-resolvert módosította; a jelenlegi resolver a normalizált összevetésben egyezik. A legacy oszlopban 4 nem-null díj és a kapcsolódó trigger/RPC továbbra is él; az adatfüggő `20260925143000` migration ezt az ágat őrzi. |
| `20260927103201 staging_clear_calendar_before_multi_user_uat_final` | **C** – egyszer használatos destruktív UAT | Tárolt SQL több booking/outbox/settlement táblán `DELETE`-et hajt végre. Újrajátszása adatvesztés, tilos. |
| `20260927103212 verify_staging_calendar_empty_before_multi_user_uat` | **C** – egyszer használatos UAT-ellenőrzés | Tárolt SQL akkori ürességet ellenőrző `DO` blokk. A jelenlegi 451 booking mellett megismétlése hibázna. |
| `20260927153341 allow_retroactive_pricing` | **D** – később felülírt | A tárolt SQL árazási RPC-ket cserél; a helyi `20260927194000` és `20260927213000` későbbi szabályokat állít be. Az érintett jelenlegi `admin_set_central_pricing` és `admin_set_user_hourly_rate` definíciói és grantek egyeznek. |
| `20260928091003 system_health_check_from_20260917100000` | **A** – ekvivalens helyi migration | A helyi `20260917100000` és a távoli SQL ugyanazt a read-only health RPC-t és anon grantot állítja elő; a jelenlegi leltár egyezik. |

Az A/B/C/D osztályozás a **jelenlegi sémahatást** rögzíti, nem jogosítja fel a history verziók átnevezését. A részletes 90→89 mapping [a PR #257 auditjában](https://github.com/ugry65/ahely-booking/blob/feature/monthly-settlement-publication/docs/STAGING_MIGRATION_HISTORY_AUDIT_2026-09-29.md) szerepel.

## Első konkrét blokkoló: `20260914095042_generic_allbooked_customer_import.sql`

Ez a helyi migration staging historyban nincs. Egy későbbi migration miatt az `admin_import_allbooked_customer` jelenlegi definíciója már egyezik a referenciával, **de három hatás nem történt meg**: a `voided` enumérték és a fenti két RPC hiányzik. A teljes történeti fájlt nem szabad replayelni, mert az import RPC korábbi definícióját visszaírná egy 451 bookingot tartalmazó staging adatbázison. A két hiányzó RPC és a production-only Papp route életciklusának bizonyítékai, valamint a `voided` érték célzott kezelésének terve a [külön döntési elemzésben](STAGING_HISTORICAL_ALLBOOKED_RPC_DECISION_2026-09-29.md) találhatók. A terv szerint a két történeti RPC-t az aktuális kívánt sémából forward migration vezeti ki; stagingre nem állítjuk vissza őket. A puszta history-repair itt hamisan állítaná, hogy a teljes migration hatása jelen van.

A `20260914120000_retire_legacy_papp_import_rpcs.sql` külön vizsgálata: a három, csak `service_role` számára futtatható régi RPC-nek 0 normál PostgreSQL dependense van, az aktuális `src` csak tesztekben hivatkozik rájuk; a fájl pontosan három `DROP FUNCTION IF EXISTS` utasítást és `BEGIN/COMMIT`-ot tartalmaz. A törlés soradatot nem módosítana, a mai alkalmazásfunkciót nem érinti, és a támadási felületet szűkíti. **Nem jelöltük appliednek és nem alkalmaztuk**, mert az előző, sorrendben korábbi `20260914095042` eltérésnél megálltunk. Későbbi kontrollált DDL és utóellenőrzés után lehet valós history-bejegyzést létrehozni.

## Folytatás feltétele

Az egyszer használatos staging UAT migrationök történeti bejegyzéseit meg kell őrizni; SQL-jüket tilos újrajátszani. A `20260914095042` objektumainak célállapotjára van [bizonyítékokra épülő döntési terv](STAGING_HISTORICAL_ALLBOOKED_RPC_DECISION_2026-09-29.md), de staging DDL előtt a projektgazda kifejezett jóváhagyása szükséges. Ezután előre mutató, verziózott, adatmegőrző DDL-lel korrigálható a séma, majd új leltár-összevetés és DB-tesztek után kezelhető a **valós** history anélkül, hogy a hiányos történeti migrationt alkalmazottnak jelölnénk. Addig sem a staging migration baseline, sem a PR #257 feature migration staging deployja nem kész.
