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

Production smoke bizonyíték, 2026-09-17:

- URL: `https://ahely-booking.vercel.app/api/health`
- HTTP státusz: `200`
- válasz: `{"ok":true,"database":"ok"}`
- `Cache-Control: no-store`

## Jogosultsági modell

A health endpoint nem használ `SUPABASE_SERVICE_ROLE_KEY` kulcsot. A Next.js route a publikus Supabase URL-t és publishable kulcsot használja, és kizárólag a külön erre a célra létrehozott RPC-t hívja.

Az RPC:

- `SECURITY INVOKER`;
- fix üres `search_path` mellett fut;
- üzleti táblát nem olvas és adatot nem módosít;
- `PUBLIC` számára nincs végrehajtási joga;
- az `anon` szerepkör számára explicit `EXECUTE` joggal rendelkezik.

Production read-only ellenőrzés, 2026-09-17:

- migration: `20260917100000_system_health_check`;
- RPC: `public.system_health_check()` létezik;
- `prosecdef = false`;
- `anon` végrehajthatja;
- `public` nem hajthatja végre.

## Production kapuk és aktuális állapot

| Kapu | Állapot | Bizonyíték / következő lépés |
|---|---|---|
| Staging migration és 200/503 smoke | Külön staging-ellenőrzés szükséges | Nem tekintjük production bizonyítéknak |
| Production deploy és publikus endpoint smoke | **PASS** | Védett production deploy; publikus `/api/health` HTTP 200 |
| Külső HTTP monitor | **PASS** | UptimeRobot HTTP monitor, 5 perces ellenőrzés |
| Kontrollált DOWN/UP alert és recovery drill | **PASS** | Szándékos 404 teszt; Down e-mail, majd URL-visszaállítás és Up recovery |
| Négy backup heartbeat monitor és riasztás igazolása | **OPEN** | A négy monitor és az élő riasztási/recovery bizonyíték dokumentálandó |

A production adatbázis-migráció, a publikus health endpoint smoke és a külső HTTP monitor DOWN/UP tesztje lezárult. A backup heartbeat monitorok külön rendszert képeznek; azok végső bizonyítékát külön kell rögzíteni.

## Külső monitor

Production monitor:

- név: `A-Hely production health`;
- URL: `https://ahely-booking.vercel.app/api/health`;
- típus: HTTP/S;
- interval: 5 perc;
- értesítés: e-mail;
- aktuális állapot: Up.

A kontrollált teszt során a monitor ideiglenesen egy nem létező URL-t kapott, amely HTTP 404 hibát adott. Az UptimeRobot Down e-mailt küldött, majd az eredeti URL visszaállítása után a monitor Up állapotba került. A teszt nem módosította a production alkalmazást vagy adatbázist.

## Backup heartbeat monitorok

A backup schedule és a négy heartbeat monitor külön rendszer a Supabase health endpointtól. A javasolt monitorok:

- `backup-08`;
- `backup-12`;
- `backup-16`;
- `backup-20`.

A backup workflow mai, kézi ellenőrzés alapján a 12:52, 16:36 és 19:52 időpontú futások sikeresek voltak. A négy heartbeat monitor végső állapot- és riasztási bizonyítéka még külön rögzítendő.

A korábbi backup release-readiness dokumentum történeti állapotot rögzít, ezért megőrzendő. Az ott szereplő production schedule-aktiválási kapu továbbra is külön kezelendő, és production environment változót nem módosítunk automatikusan.
