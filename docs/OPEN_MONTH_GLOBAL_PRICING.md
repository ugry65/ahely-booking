# Nyitott aktuális hónap díjszabása – #295

## Követelmény és határ

2026-10-13: nyitott hónapban a hónap első napjától lehessen díjszabást beállítani (október 13-án október 1-től). Implementációs engedély: „Módosítsd”. Az aktuális budapesti hónapra valósul meg; korábbi nyitott hónap globális átárazása nem része a scope-nak. Production csak külön elfogadás/GO után.

Állapot: projektgazdai staging elfogadás és production GO után 2026-10-14-én élesítve (#298). A staging átadás és független review alább történeti bizonyítékként megmarad. Review: [INDEPENDENT_REVIEW.md](evidence/2026-10-13-open-pricing/INDEPENDENT_REVIEW.md).

## Production kiadás – 2026-10-14

- Imre 12:58 Europe/Budapest: „Rendben van , telepít hetes az éles rendszerbe”. Ez a staging felhasználói elfogadása és kifejezett élesítési GO; nem új saját tételes bejelentkezett UI-UAT.
- Elfogadott main/staging SHA `fcdc57eaad6a69e230402c0224ce078743572919`, staging READY `dpl_5KVWocUV74Nr5ZGxovbUEeuZe3f4`. Release [#298](https://github.com/ugry65/ahely-booking/pull/298) normál main → production merge. Production SHA `710f875a668ba3d87747ba227e29a82488754c4b`; merge tree byte-pontosan az elfogadott main tree-je.
- Production deployment `dpl_79CW8kmFYdMW1KwdtdKCaAcAyLhr`: READY, production target/ref/pontos SHA és `foglalas.a-hely.com` alias igazolt. Használat: https://foglalas.a-hely.com/admin/dijszabas.
- Production Supabase `yasrmxwjojepessivhmc`: csak az egyetlen reviewed SQL migration API-val alkalmazva; actual version `20261014110645`, name `allow_current_open_month_global_pricing`, stored SQL byte-exact, MD5 `c39cffa328a78960f9cca30b398333d7`. Canonical local20261013205742 SHA256 `87d98c68245966d9381a769b56f697302aa4911386519e8b9f08f9934d439b3e`. Staging actual version eltér, de SQL azonos. Nincs bulk push, régi migration replay, remote history repair vagy CLI dry-run állítás.
- Production preflight: mindkét régi RPC bodyja byte-pontosan a canonical future-only forrás; grant/search_path/szignatúra várt. Post-check: mindkét új body exact reviewed SQL, SECURITY DEFINER/üres search_path; anon execute=false, authenticated/service_role=true, szignatúra változatlan. Mind a90korábbi historysor változatlan,91actual applied row.
- Tarifa/special_rate/revision/booking_line sorhash és darabszám előtte/utána egyezik:6/2/63/883. Nem állítottunk be új díjat vagy zártunk üzleti hónapot. Production október nyitott; a UI close-preview RPC return contractja megfelelő. Securityadvisor baseline számai változatlanok.
- Friss release PR CI Production release gate/application-checks/evidence-consistency/database-tests SUCCESS. Helyi297 Vitest/typecheck/release-evidence --release PASS; az elfogadott SQL-hez791 pgTAP és concurrency PASS. Legutóbb megfigyelt sikeres production backup job115573789035 (2026-10-13 22:32 UTC) artifactját mindkét független célhelyen read-back ellenőrizte; ez nem új restore-drill.
- Éles health HTTP200 / ok=true / database=ok, védett admin route307→belepes; új deployment error/fatal aggregáció nem adott találatot. Ez technikai smoke, nem saját bejelentkezett UI-UAT.
- BOOKING_EMAIL_MODE=disabled és production Supabase URL frissen ellenőrizve; config nem változott. SITE_URL sensitive értékét az API nem adja vissza; a változatlan identity guard az új sikeres production buildben validálta a cél-konfigurációt.
- Visszaállítható alkalmazás baseline: SHA `e15ac2330c76840a673bf55fea5a8c7301682fff`, deployment `dpl_EwQ9jFw25ooiXbAU7egAroSBcJBG`. Szükség esetén a korábbi RPC-definíció csak külön forward rollback migrációval állítható vissza; üzleti adatok visszatöltése nem szükséges. Visszaállítás nem történt.

## Staging átadás – 2026-10-13

- Implementáció main SHA `5e78ca06afddc009c076b65f0d3d6036ec692043` (#296). Merge előtti HEAD550e2ad összes CI-je SUCCESS; migration/page az eredetileg reviewed576b23c blobokkal egyezik.
- Staging READY deployment `dpl_31f6cA8BCTrtGxCnFiN4Bqg1eNuf`, pontos main SHA/ref és stabil alias ellenőrizve. Kipróbálás: https://ahely-booking-staging-web.vercel.app/admin/dijszabas.
- Supabase staging `fvwapntzhavhgazeflri`: actual migration `20261013214532 / allow_current_open_month_global_pricing`, stored SQL bájtszinten egyezik a canonical20261013205742 fájllal; MD5 `c39cffa328a78960f9cca30b398333d7`, canonical SHA256 `87d98c68245966d9381a769b56f697302aa4911386519e8b9f08f9934d439b3e`.
- Mindkét élő RPC body/szignatúra/SECURITY DEFINER/üres search_path/anon tiltás/authenticated grant pontos. A 93 korábbi history rekord változatlan, egy valós új applied row hozzáadva; nincs history-repair. Friss pin/projection:94 applied, pending=[]; a CLI dry-run nem történt, az ellenőrzés read-only history-pinnelt single-migration API preflight volt.
- A migration előtt/után tariffa/special_rate/revision/booking_line darabszámok és teljes sorhash-ek egyeznek; booking darabszám452 változatlan. Nem állítottunk be új valódi díjat vagy zártunk üzleti hónapot. Securityadvisor baseline számai változatlanok (a meglévő deny-by-default RLS/guarded RPC és Auth figyelmeztetések nem új regressziók).
- Health HTTP200 / ok=true / database=ok; admin/dijszabas bejelentkezés nélkül307→/belepes. Új deployment error/fatal aggregált lekérdezés nem adott találatot. Ez nem bejelentkezett UI-UAT.
- Production ág változatlan SHA `e15ac2330c76840a673bf55fea5a8c7301682fff`; production DB-migráció, konfiguráció- vagy üzleti adatírás nem történt. Külön élesítési GO szükséges.

## Működés

- Admin → Díjszabás: központi sávos és Tréningterem csoportos díj kezdődátumának minimuma/alapértéke a nyitott aktuális hónap első napja.
- Az élő kalkuláció a már megtörtént foglalásokat is újraszámolja a megadott kezdődátumtól. Meglévő későbbi tarifa kezdetén az új időszak véget ér; a későbbi tarifa nem íródik át.
- Lezárt aktuális hónap esetén a UI a következő hónap első napját ajánlja. A DB a lezárt hónap minden kezdődátumát elutasítja, elavult UI-ból is.
- Booking/user egyedi díj elsőbbsége, havi sávhatár, rounding és immutable settlement snapshot változatlan. Automatikus új revision nem készül.
- Megmarad a kötelező indok, aktív admin, before/after audit és DB átfedésvédelem. Az azonos kezdődátum meglévő tarifát szerkeszt, nem duplikál időszakot; minden admin művelet külön auditált.

## DB-védelem és konkurencia

Migration: `20261013205742_allow_current_open_month_global_pricing.sql` (Supabase CLI migration new). Két meglévő RPC változik, szignatúrájuk/grantjuk változatlan; nincs új tábla, RLS vagy kliensjogosultság.

A tarifa-specifikus advisory lock után a setter megszerzi a hónapzáró RPC által használt `monthly-settlement-period:YYYY-MM-01` tranzakciós advisory lockot. Ezután ellenőrzi a period-publikációt és a legacy user-szintű is_closed flaget. A hónap első napi alsó dátumhatárt a várakozás után is ellenőrzi a budapesti hónapforduló miatt.

- Tarifa nyer: a zárás megvárja a commitot, és az új díjat snapshotolja.
- Zárás nyer: a setter commit után tiltással és teljes rollbackkel áll meg.
- UI: requireAdmin + session kliens + meglévő close-preview RPC. Hibás/hiányos/eltérő hónapállapot esetén a mentés tiltott. A DB a végső authority.

## Tesztek és bizonyítéki határ

- `admin-pricing-dates.test.ts`: október 13 → október 1, Budapest éjfél, hónap-/évforduló, DST, lezárt → következő hónap.
- `admin/dijszabas/page.test.tsx`: mindkét dátummező, admin RPC, lezárt hónap, fail-closed állapot.
- `116_global_pricing_future_only.sql`: történeti fájlnév, új pgTAP policy. Valódi close RPC, újraszámolás, egyedi díjprioritás, későbbi verzió megőrzése, snapshot hash, negatív/jogosultsági tesztek, audit rollback.
- `test-open-month-pricing-concurrency.sh`: csak localhost DB, külön psql kapcsolatok, pg_stat_activity/pg_blocking_pids alapú igazolt várakozás; központi setter→close és close→központi/Tréningterem setter ágak. Külön training→close ág nincs. A DB runner/CI végén fut, mert publikálja a lokális fixture hónapot. A korábbi race-ek jövőbeli fixture bookingjai miatt kizárólag a close tranzakcióban 31 napos cutoffot használ, majd az eredeti értéket ugyanazon tranzakció commitja előtt visszaállítja; ezt külön ellenőrzi. Ez teszt setup, nem üzleti cutoff-változás.
- Helyi ellenőrzés a dátumhoz tartozó díjelőtöltéssel együtt: 297/297 Vitest, typecheck, Next.js build, diff-check és release-evidence --release PASS. A form az alapértelmezett kezdődátumra érvényes tarifát tölti elő, nem egy későbbi ütemezett változást.
- Feature HEAD `576b23c2a510050af7bdf3264335bb3a5f0e1592` Database tests run38468679068 SUCCESS: 47 pgTAP fájl, 791 teszt és teljes concurrency suite PASS. Application/evidence-consistency/isolated-reference SUCCESS. Helyi Docker/psql nem áll rendelkezésre. Élő bejelentkezett staging UAT nincs igazolva.

## Független review

Ellenőrizendő: aktuális hónap scope, lezárt napok tiltása; lock-sorrend és publication check a várakozás után; korábbi snapshot/díjfeloldás és későbbi verzió megőrzése; admin-only/fix search_path/ACL; null/negatív/infinite input és audit rollback; UI fail-closed/Budapest hónapforduló; a tesztben használt cutoff helyreállítása és kizárólag lokális cél.

## Bevezetés

CI PASS + független review után staging migráció és PR → main (staging branch). A bulk staging DB workflow helyett elérhető Supabase migration API kizárólag az explicit reviewed SQL-t alkalmazhatja. Előfeltétel a read-only projekt/history/SQL előellenőrzés és a változatlan staging projection guard pontos pending-listája. A CLI dry-run nem állítható lefutottnak pusztán a projection alapján. Cél kizárólag `fvwapntzhavhgazeflri`; production `yasrmxwjojepessivhmc`/production ág nem módosulhat. A migration API által kiosztott valódi version/name és SQL hash utólag pinelendő; nem javítunk mesterségesen távoli historyt.

UAT: Admin → Díjszabás → aktuális hónap első napjától új tesztdíj/indok → havi élő összeg változása; egyedi díj változatlan; lezárt hónap kísérlete tiltott. Valós staging pénzügyi adatot csak egyeztetett tesztazonosítóval változtatunk. A migration önmagában nem ír tarifát vagy üzleti adatot.
