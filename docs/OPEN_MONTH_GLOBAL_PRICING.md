# Nyitott aktuális hónap díjszabása – #295

## Követelmény és határ

2026-10-13: nyitott hónapban a hónap első napjától lehessen díjszabást beállítani (október 13-án október 1-től). Implementációs engedély: „Módosítsd”. Az aktuális budapesti hónapra valósul meg; korábbi nyitott hónap globális átárazása nem része a scope-nak. Production csak külön elfogadás/GO után.

Állapot: implementált feature ág, CI/review előkészítés. Staging DB-migráció/stabil telepítés még nincs. Független pénzügyi/security review hiányzik; AGENTS.md szerint ez kötelező merge/telepítési kapu.

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
- `test-open-month-pricing-concurrency.sh`: csak localhost DB, külön psql kapcsolatok, pg_stat_activity/pg_blocking_pids alapú igazolt várakozás, mindkét sorrend és mindkét setter. A DB runner/CI végén fut, mert publikálja a lokális fixture hónapot. A korábbi race-ek jövőbeli fixture bookingjai miatt kizárólag a close tranzakcióban 31 napos cutoffot használ, majd az eredeti értéket ugyanazon tranzakció commitja előtt visszaállítja; ezt külön ellenőrzi. Ez teszt setup, nem üzleti cutoff-változás.
- Helyi ellenőrzés a dátumhoz tartozó díjelőtöltéssel együtt: 297/297 Vitest, typecheck, Next.js build, diff-check és release-evidence --release PASS. A form az alapértelmezett kezdődátumra érvényes tarifát tölti elő, nem egy későbbi ütemezett változást.
- DB CI eredmény még nincs rögzítve. Helyi Docker/psql nem áll rendelkezésre. Élő staging UAT nincs igazolva.

## Független review

Ellenőrizendő: aktuális hónap scope, lezárt napok tiltása; lock-sorrend és publication check a várakozás után; korábbi snapshot/díjfeloldás és későbbi verzió megőrzése; admin-only/fix search_path/ACL; null/negatív/infinite input és audit rollback; UI fail-closed/Budapest hónapforduló; a tesztben használt cutoff helyreállítása és kizárólag lokális cél.

## Bevezetés

CI PASS + független review után PR → main (staging branch). Staging DB workflow: dry-run → pontos pending migration lista → deploy. Cél kizárólag `fvwapntzhavhgazeflri`; production `yasrmxwjojepessivhmc`/production ág nem módosulhat.

UAT: Admin → Díjszabás → aktuális hónap első napjától új tesztdíj/indok → havi élő összeg változása; egyedi díj változatlan; lezárt hónap kísérlete tiltott. Valós staging pénzügyi adatot csak egyeztetett tesztazonosítóval változtatunk. A migration önmagában nem ír tarifát vagy üzleti adatot.
