# Production health és uptime monitoring

## Cél

A production alkalmazás rendelkezzen külsőleg monitorozható, személyes vagy üzleti adatot nem közlő health endpointtal, amely a Next.js alkalmazás mellett a Supabase/PostgreSQL elérhetőségét is ténylegesen ellenőrzi.

Kapcsolódó issue: #102. A korábbi #114 anti-pause feladat ebbe a mechanizmusba lett konszolidálva.

## `/api/health` kontraktus

A publikus `GET /api/health` végpont:

- dinamikus, nem cache-elhető;
- minden kérésnél meghívja a `public.system_health_check()` PostgreSQL RPC-t;
- egészséges DB-kapcsolatnál HTTP 200-at ad;
- DB/RPC/konfigurációs hiba esetén fail-closed HTTP 503-at ad;
- csak az összesített állapotot és a mérés válaszidejét közli;
- nem ad vissza SQL hibát, adatbázis-azonosítót, rekordot, személyes adatot vagy secretet.

Példa sikeres válasz:

```json
{"ok":true,"database":"ok","responseTimeMs":12}
```

Példa hibás válasz:

```json
{"ok":false,"database":"error","responseTimeMs":12}
```

## Jogosultsági modell

A health endpoint nem használ `SUPABASE_SERVICE_ROLE_KEY` kulcsot. A Next.js route a publikus Supabase URL-t és publishable kulcsot használja, és kizárólag a külön erre a célra létrehozott `system_health_check()` RPC-t hívja.

Az RPC:

- `SECURITY INVOKER`;
- fix üres `search_path` mellett fut;
- üzleti táblát nem olvas és adatot nem módosít;
- `PUBLIC` számára nincs végrehajtási joga;
- az `anon` szerepkör számára explicit `EXECUTE` joggal rendelkezik.

Ez a PostgREST → PostgreSQL útvonal tényleges működését ellenőrzi, miközben a health mechanizmusnak nem ad hozzáférést foglalási, felhasználói vagy pénzügyi adatokhoz.

## Anti-pause hatás

A külső uptime monitor minden `/api/health` kérésnél valódi, read-only adatbázis-műveletet vált ki. A #102-ben rögzített rendszeres UptimeRobot ellenőrzés ezért egyben legitim production DB-aktivitást is biztosít.

## Következő production lépések

A kód merge/deploy önmagában még nem zárja le a #102 issue-t. Production GO előtt még szükséges:

1. stagingen a 200-as egészséges és kontrollált 503-as hibás állapot bizonyítása;
2. production deploy után a publikus health endpoint smoke ellenőrzése;
3. UptimeRobot HTTP monitor létrehozása és az alert cél beállítása;
4. kontrollált DOWN/UP alert + recovery drill;
5. a négy backup heartbeat monitor (`backup-08`, `backup-12`, `backup-16`, `backup-20`) összekötése a production backup folyamattal;
6. az eredmények rögzítése a production UAT/üzemeltetési dokumentációban.

A backup heartbeat implementáció a #101 production backup automatizmushoz kapcsolódik; a #102 csak akkor tekinthető teljesnek, ha a külső monitorozás és az alert/recovery bizonyított.
