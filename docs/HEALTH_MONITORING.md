# Production health és uptime monitoring

## Cél

A production alkalmazás rendelkezzen külsőleg monitorozható health endpointtal, amely a Next.js alkalmazás mellett a Supabase/PostgreSQL elérhetőségét is ténylegesen ellenőrzi.

Kapcsolódó issue: #102. Ez kiegészíti a külön GitHub Actions Supabase availability health-checket.

## /api/health kontraktus

A publikus `GET /api/health` végpont:

- dinamikus, nem cache-elhető;
- minden kérésnél meghívja a `public.system_health_check()` PostgreSQL RPC-t;
- egészséges DB-kapcsolatnál HTTP 200-at ad;
- DB/RPC/konfigurációs hiba esetén fail-closed HTTP 503-at ad;
- csak az összesített állapotot és a mérés válaszidejét közli;
- nem ad vissza SQL hibát, adatbázis-azonosítót, rekordot, személyes adatot vagy secretet.

Sikeres válasz:

```json
{"ok":true,"database":"ok","responseTimeMs":12}
```

Hibás válasz:

```json
{"ok":false,"database":"error","responseTimeMs":12}
```

## Jogosultsági modell

A health endpoint nem használ `SUPABASE_SERVICE_ROLE_KEY` kulcsot. A Next.js route a publikus Supabase URL-t és publishable kulcsot használja, és kizárólag a külön erre a célra létrehozott RPC-t hívja.

Az RPC:

- `SECURITY INVOKER`;
- fix üres `search_path` mellett fut;
- üzleti táblát nem olvas és adatot nem módosít;
- `PUBLIC` számára nincs végrehajtási joga;
- az `anon` szerepkör számára explicit `EXECUTE` joggal rendelkezik.

## Production kapuk

A kód és a migration PR-ban történő merge-e nem módosítja automatikusan a production adatbázist. Production előtt külön szükséges:

1. staging migration és 200/503 smoke;
2. production deploy és publikus endpoint smoke;
3. UptimeRobot vagy más külső HTTP monitor létrehozása;
4. kontrollált DOWN/UP alert és recovery drill;
5. a négy backup heartbeat monitor meglétének és riasztásának igazolása.

Ezek közül a külső monitor, alert/recovery és production deploy kézi üzemeltetési lépés.
