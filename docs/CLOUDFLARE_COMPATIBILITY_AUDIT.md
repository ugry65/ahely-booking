# Cloudflare Workers / OpenNext kompatibilitási audit

Dátum: 2026-08-22
Branch: `chore/cloudflare-deployment-test`
Issue: #85
PR: #86

## Cél és hatókör

Ez a munka kizárólag párhuzamos Cloudflare Workers teszt. A meglévő Vercel production, domain és Supabase backend változatlan marad. Cloudflare-specifikus üzleti logika és adatbázis-módosítás nem része ennek a kísérletnek.

## Hivatalos technikai irány

A 2026-08-22-i Cloudflare Workers Next.js dokumentáció az `@opennextjs/cloudflare` adaptert ajánlja. A jelenlegi OpenNext dokumentáció szerint minden Next.js 16 minor/patch verzió támogatott. A Cloudflare oldali futtatás Workers/workerd runtime-ban történik, `nodejs_compat` flaggel.

Hivatalos források:
- https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/
- https://opennext.js.org/cloudflare
- https://opennext.js.org/cloudflare/get-started

A branch által lockolt verziók:
- `@opennextjs/cloudflare`: 1.20.2
- `wrangler`: 4.125.0
- Next.js: 16.3.1

## Repository audit

### Next.js runtime

- App Router használatban.
- Nincs `export const runtime = "edge"` deklaráció.
- Nincs explicit Node runtime deklaráció.
- OpenNext Node.js runtime modellje ezért illeszkedik a jelenlegi alkalmazáshoz.

### Proxy / middleware

A Next.js 16 `proxy.ts` a `src/lib/supabase/proxy.ts` session-frissítő rétegét hívja.

A proxy jelenleg:
- `NextRequest` / `NextResponse` API-kat használ;
- `@supabase/ssr` klienst használ;
- request/response cookie-kat kezel;
- `supabase.auth.getClaims()` hívást végez;
- nem használ `fs`-t vagy explicit `node:` importot.

Kockázat: a Cloudflare dokumentáció szerint a Node.js runtime middleware/proxy még nem támogatott. A jelenlegi proxy kód Web/Next kompatibilis API-kat használ, ezért várhatóan működőképes, de ezt OpenNext build + workerd runtime + valódi auth smoke teszttel kötelező bizonyítani.

### Node.js-specifikus API / filesystem

A repository audit során nem találtunk alkalmazáskódban:
- `node:` importot;
- `fs` filesystem használatot;
- lokális tartós fájlrendszerre támaszkodó üzleti logikát.

Ez kedvező Workers-kompatibilitási jel.

### Server Actions

Az alkalmazás több `"use server"` actiont használ, többek között auth, foglalás és admin funkciókhoz. A Cloudflare/OpenNext jelenlegi dokumentáció szerint Server Actions támogatottak. Ezt runtime smoke tesztben külön ellenőrizni kell.

### Route Handlers

Auth callback és admin CSV export route handlerek vannak. Ezek szabványos Next.js `Request` / `Response` / `NextRequest` / `NextResponse` API-kat használnak. A Cloudflare/OpenNext Route Handlers támogatottként jelölt funkció.

### Supabase SSR / Auth / cookie

A `src/lib/supabase/server.ts` a `cookies()` Next API-t és az `@supabase/ssr` cookie adaptert használja. A proxy ugyanezt a session modellt követi request/response cookie-kkal.

Nem találtunk Vercel-specifikus auth API-t. Ezért nincs előzetes vendor-lock-in akadály, de valódi Cloudflare preview alatt kötelező ellenőrizni:
- login;
- logout;
- session fennmaradás;
- cookie frissítés;
- auth callback;
- password-reset redirect.

### Environment változók

Cloudflare build/runtime környezetben szükséges:
- `NEXT_PUBLIC_SUPABASE_URL` – staging Supabase URL;
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` – staging publishable key;
- `SUPABASE_SERVICE_ROLE_KEY` – **secret**, kizárólag Worker/server runtime-ban;
- `SITE_URL` – a Cloudflare preview Worker URL-je.

A valódi értékek nem kerülhetnek repositoryba vagy logba.

A `SITE_URL` miatt a Cloudflare preview URL-t a Supabase Auth engedélyezett redirect URL-jeihez hozzá kell adni úgy, hogy a Vercel production redirect továbbra is megmaradjon.

### Adatbiztonság

A kritikus foglalási üzleti logika és ütközésvédelem PostgreSQL/Supabase oldalon marad. A Cloudflare adapter nem változtatja meg:
- az adatbázis-szintű overlap védelmet;
- az RPC jogosultsági ellenőrzéseket;
- a tranzakciókat;
- az auditnaplót;
- a booking concurrency védelmet.

Ez a hosting-kísérlet ezért nem indokol Supabase migrációt.

## Előzetes kompatibilitási kockázatok

1. **Proxy / auth cookie runtime** – közepes kockázat, tényleges workerd és preview auth teszt szükséges.
2. **Worker bundle size** – mérendő; Workers Paid limitet a build/deploy output alapján ellenőrizni kell.
3. **Cloudflare adapter dependency** – technikai vendor adapter, de az üzleti kód szabványos Next.js marad. Visszafordítható: a Wrangler/OpenNext config eltávolítható.
4. **Caching** – az első tesztben nem vezetünk be R2/Cloudflare-specifikus cache-t. Ez csökkenti a lock-int és a változókat.
5. **Environment / Auth redirect** – külön staging konfiguráció szükséges; production Vercel URL nem írható felül.

## Előzetes minősítés

**Nincs jelenleg azonosított blokkoló inkompatibilitás.**

A végleges minősítés csak az alábbiak után adható:
- frozen dependency install;
- meglévő tesztek;
- TypeScript typecheck;
- normál Next.js build;
- OpenNext build;
- workerd/Wrangler local smoke;
- Cloudflare preview deployment;
- valódi staging Supabase auth/session/foglalási smoke.
