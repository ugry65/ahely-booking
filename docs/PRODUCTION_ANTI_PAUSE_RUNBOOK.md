# Production Supabase Free anti-pause runbook

Dátum: 2026-09-09
Kapcsolódó issue: #114

## Cél

A production Supabase Free projekt rendszeres, legitim read-only aktivitást kapjon, és egyben legyen proaktív adatbázis-elérhetőségi ellenőrzés. Ez availability-védelem; nem backup-mechanizmus.

## Incidens előzmény

2026-09-09-én az `ahely-booking-production` Supabase projekt 7 nap alacsony aktivitás után automatikusan pause állapotba került. A projekt manuálisan fel lett oldva. A Supabase Free költségbaseline változatlan.

A Supabase aktuális dokumentációja szerint a Free projekt akkor kerülhet automatikusan pause állapotba, ha a megelőző 7 napban nincs elegendő felhasználói adatbázis-aktivitás. A dokumentáció szerint tipikusan napi néhány adatbázis-kérés elegendő a pause elkerüléséhez. Emiatt nem napi egyetlen pinget használunk, hanem napi négy valódi, read-only adatbázis-lekérdezést.

## Megoldás

Production Vercel Cron naponta négyszer meghívja:

`GET /api/internal/production-health`

Ütemezés UTC-ben:

- 00:15
- 06:15
- 12:15
- 18:15

Ez 7 nap alatt 28 valódi adatbázis-kérést eredményez akkor is, ha nincs normál felhasználói forgalom.

Az endpoint:

1. kizárólag helyes `Authorization: Bearer <CRON_SECRET>` fejlécet fogad el;
2. server-side Supabase admin klienssel egy minimális read-only `SELECT` lekérdezést futtat az `app_settings` táblán;
3. siker esetén csak `{ "ok": true }` választ ad;
4. DB-hiba esetén 503-at ad;
5. jogosulatlan kérésre 401-et ad;
6. nem ír üzleti adatot, nem hoz létre audit-, foglalási- vagy elszámolási rekordot;
7. nem ad vissza rekordadatot, személyes adatot vagy secretet;
8. `Cache-Control: no-store` választ ad, tehát minden cron futás tényleges backend/DB ellenőrzés.

## Vercel konfiguráció

A cron definíciók a repository gyökerében lévő `vercel.json` fájlban vannak. Vercel Cron kizárólag production deploymentben aktiválódik.

A `CRON_SECRET` már a projekt belső cron/worker védelmének része; productionben hosszú, véletlen secretként Vercel Environment Variable-ben kell lennie. A Vercel Cron ezt Bearer tokenként küldi. A secret nem kerülhet repository-ba, dokumentációba vagy logba.

## Production release előtt kötelező ellenőrzés

- `CRON_SECRET` létezik a Vercel Production környezetben;
- `pnpm test` sikeres;
- `pnpm typecheck` sikeres;
- production deploy után a Vercel Cron listában mind a négy ütemezés megjelenik;
- kézi cron teszt helyes tokennel 200-at ad;
- Authorization nélkül az endpoint 401-et ad;
- működő DB-nél `{ "ok": true }`;
- endpoint válasza nem tartalmaz DB adatot vagy hibadetailt;
- Supabase project státusz aktív marad;
- legalább 8 napos megfigyelés után igazolni kell, hogy nem következik be automatikus pause.

Production deploy csak explicit tulajdonosi jóváhagyással történhet.

## Hiba esetén

Ha cron futás 503-at ad:

1. ellenőrizni kell a Supabase project státuszát;
2. ellenőrizni kell a Vercel runtime logot;
3. pause esetén a projektet manuálisan unpause-olni kell;
4. az anti-pause megoldás hibáját incidensként kezeljük és javítjuk.

Ha a Supabase 540 állapotot jelez, az a projekt pause állapotára utal.

A health-check nem helyettesíti a már tesztelt Google Drive + Backblaze B2 backup/restore rendszert.