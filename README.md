# A-Hely foglalási rendszer

Az A-Hely saját, magyar nyelvű foglalási és havi elszámolási webalkalmazása.

## Állapot

A technikai architektúra, az adatmodell és a PostgreSQL-séma alapjai elkészültek. Az Auth/RLS mérföldkő fejlesztés alatt áll. Production használatra még nem alkalmas.

## Kötelező források

- `docs/TECHNIKAI_ARCHITEKTURA_ES_ADATMODELL.md`
- `docs/source/A-Hely_Foglalasi_Rendszer_Funkcionalis_Specifikacio_v1.0.docx`
- `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`

Ellentmondás esetén az aktuális FS és projektkontextus az irányadó.

## Első fejlesztési mérföldkő

1. PostgreSQL-séma és adatbázis-kényszerek
2. Auth és RLS
3. tranzakciós foglalás-létrehozás
4. automatikus adatbázistesztek
5. független review

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
