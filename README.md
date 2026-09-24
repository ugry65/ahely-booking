# A-Hely foglalási rendszer

Az A-Hely saját, magyar nyelvű foglalási és havi elszámolási webalkalmazása.

## Állapot

**2026-09-24:** a foglalási mag, Auth/RLS, jogosultságok, admin/user naptár, ismétlődés, lemondás, AllBooked együgyfeles migráció, booking e-mail outbox/worker, admin díjszabás, user- és foglalásszintű óradíj, havi pricing kimutatás és részletes export mainben implementált. A korábbi funkcionális staging UAT elfogadásai érvényesek; a PR #179–#184 pricing változtatási kör célzott regressziós UAT-ja **12/12 PASS**.

A staging és production elkülönül. Production adatbázis-migráció, booking e-mail send aktiválás és végső release csak külön jóváhagyott release-folyamatban történhet. A repository aktuális állapota ezért **release-előkészítési / production-readiness fázis**, nem automatikus production GO.

Aktuális bizonyítékok és státusz: `docs/RELEASE_EVIDENCE.md`, `docs/UAT_FUTASI_JEGYZOKONYV.md`, `docs/BOOKING_EMAIL_PRODUCTION_READINESS.md`.

## Kötelező források

- `docs/TECHNIKAI_ARCHITEKTURA_ES_ADATMODELL.md`
- `docs/source/A-Hely_Foglalasi_Rendszer_Funkcionalis_Specifikacio_v1.0.docx`
- `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`

Ellentmondás esetén az aktuális FS és projektkontextus az irányadó.

## Fejlesztési / release munkamód

1. üzleti követelmény és FS ellenőrzése;
2. technikai terv és adatmodell;
3. külön branch/PR;
4. automatikus tesztek és kritikus résznél független review;
5. staging migráció és célzott UAT;
6. dokumentált release-evidence;
7. production csak külön jóváhagyással és visszaállíthatósági kapuk után.

## Helyi előfeltételek

- Node.js LTS
- pnpm
- Docker
- Supabase CLI

## Webalkalmazás

```bash
cp .env.example .env.local
pnpm install
pnpm dev
```

A `.env.local` értékeit a helyi `supabase status` kimenete alapján kell kitölteni. A `SUPABASE_SERVICE_ROLE_KEY` kizárólag szerveroldali admin Auth-művelethez használható; `NEXT_PUBLIC_` előtaggal vagy klienskódban tilos szerepeltetni.

Statikus és production build ellenőrzés:

```bash
pnpm typecheck
pnpm build
```

## Adatbázis-validálás

A Supabase CLI a helyi PostgreSQL-környezetet Dockerben indítja. A teljes ellenőrzés:

```bash
./scripts/test-database.sh
```

A parancs:

1. elindítja a helyi adatbázist;
2. üres állapotból alkalmazza az összes migrációt és seedet;
3. lefuttatja a `supabase/tests` pgTAP tesztjeit;
4. lefuttatja a PostgreSQL schema lintet.

Ugyanez minden adatbázist érintő pull requestnél automatikusan lefut a GitHub Actions környezetben.

Az Auth/RLS ág a Next.js App Router vázat, a Supabase SSR munkamenet-kezelést, az e-mail+jelszó folyamatokat, az adminmeghívást és az adatbázis-szintű deny-by-default jogosultságokat tartalmazza.
