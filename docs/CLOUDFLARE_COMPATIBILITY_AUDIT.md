# Cloudflare Workers / OpenNext kompatibilitási audit

Dátum: 2026-08-22
Branch: `chore/cloudflare-deployment-test`
Issue: #85
PR: #86

## Cél és hatókör

Ez a munka kizárólag párhuzamos Cloudflare Workers teszt. A meglévő Vercel production, domain és Supabase backend változatlan marad. Cloudflare-specifikus üzleti logika és adatbázis-módosítás nem része ennek a kísérletnek.

## Hivatalos technikai irány

A 2026-08-22-i Cloudflare Workers Next.js dokumentáció az `@opennextjs/cloudflare` adaptert ajánlja. A Cloudflare oldali futtatás Workers/workerd runtime-ban történik `nodejs_compat` flaggel.

Hivatalos források:
- https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/
- https://opennext.js.org/cloudflare
- https://opennext.js.org/cloudflare/get-started
- https://github.com/opennextjs/opennextjs-cloudflare/issues/1277
- https://github.com/opennextjs/opennextjs-cloudflare/issues/1279
- https://developers.cloudflare.com/workers/platform/pricing/
- https://developers.cloudflare.com/workers/platform/limits/

A branch által lockolt verziók:
- `@opennextjs/cloudflare`: 1.20.2
- `wrangler`: 4.125.0
- Next.js: 16.3.1

## Repository audit

### Next.js runtime

- App Router használatban.
- Nincs `export const runtime = "edge"` deklaráció.
- Nincs explicit Node runtime deklaráció a route-okban.
- A szerveroldali alkalmazáskód általánosan kompatibilis a Workers `nodejs_compat` rétegével.

### Proxy / middleware — BLOKKOLÓ

A Next.js 16 `proxy.ts` a `src/lib/supabase/proxy.ts` session-frissítő és route-védelmi rétegét hívja.

A proxy jelenleg:
- `NextRequest` / `NextResponse` API-kat használ;
- `@supabase/ssr` klienst használ;
- request/response cookie-kat kezel;
- `supabase.auth.getClaims()` hívást végez;
- nem használ `fs`-t vagy explicit `node:` importot.

A kompatibilitási build azonban empirikusan elbukik OpenNext 1.20.2 + Next.js 16.3.1 kombinációnál. A normál Next.js build sikeres, majd az OpenNext bundle-generálás ezt a hibát adja:

```text
Error: This error should only happen for static 404 and 500 page from page router.
File server/middleware.js does not exist
```

A hiba a `@opennextjs/aws` `copyTracedFiles` / OpenNext Cloudflare bundle-generálási útvonalán történik, közvetlenül a middleware/proxy bundle készítésekor.

Ez összhangban áll az OpenNext jelenleg nyitott #1277 hibájával: a Next.js 16 `proxy.ts` Node.js middleware/proxy konvenció Cloudflare Workers támogatása még nincs kész. A #1279 ugyanezt a hiányzó támogatást írja le, és #1277 duplikátumaként zárták.

### Miért blokkoló az A-Hely számára?

A `proxy.ts` nem opcionális dekoráció: a Supabase session frissítés és a védett route-ok korai auth kezelése fut benne. A Next.js 16 dokumentációban a Proxy a jelenlegi szabványos mechanizmus az ilyen request-előtti auth/routing logikára.

Ezért nem fogadható el olyan Cloudflare-workaround, amely:
- egyszerűen eltávolítja a proxyt;
- kikapcsolja a session-frissítést;
- gyengíti a védett route-ok auth ellenőrzését;
- OpenNext belső bundle-fájljait kézzel patch-eli;
- az alkalmazásba Cloudflare-specifikus auth-elágazást épít.

### Lehetséges utak

1. **Várni az OpenNext hivatalos `proxy.ts` támogatására — AJÁNLOTT.**
   - nincs alkalmazáskód-változás;
   - nincs auth regresszió;
   - minimális vendor lock-in;
   - később ugyanazon tesztbranch friss adapterrel újrafuttatható.

2. **Next.js 15 Maintenance LTS-re visszalépni és Edge middleware-t használni.**
   - technikailag lehetséges alternatíva lehet;
   - de az egész projekt framework-verzióját érintené;
   - jelen feladat céljához aránytalan és kockázatos;
   - csak külön architekturális döntéssel lenne elfogadható.

3. **OpenNext saját/PR patch használata.**
   - magas vendor-lock-in és karbantartási kockázat;
   - auth/security szempontból érzékeny build-runtime patch;
   - az A-Hely projekthez nem javasolt.

## Node.js-specifikus API / filesystem

A repository audit során nem találtunk alkalmazáskódban:
- `node:` importot;
- `fs` filesystem használatot;
- lokális tartós fájlrendszerre támaszkodó üzleti logikát.

Ez kedvező Workers-kompatibilitási jel.

## Server Actions

Az alkalmazás több `"use server"` actiont használ, többek között auth, foglalás és admin funkciókhoz. A Cloudflare/OpenNext dokumentáció szerint Server Actions támogatottak. A bundle-blokkoló miatt runtime smoke tesztjük még nem volt lehetséges.

## Route Handlers

Auth callback és admin CSV export route handlerek vannak. Ezek szabványos Next.js `Request` / `Response` / `NextRequest` / `NextResponse` API-kat használnak. A normál Next.js build és az OpenNext belső Next-build fázisa ezeket sikeresen fordította.

## Supabase SSR / Auth / cookie

A `src/lib/supabase/server.ts` a `cookies()` Next API-t és az `@supabase/ssr` cookie adaptert használja. A proxy ugyanezt a session modellt követi request/response cookie-kkal.

Nem találtunk Vercel-specifikus auth API-t. Maga a Supabase SSR réteg ezért nem azonosított inkompatibilitási ok; a blokkoló az adapter Next.js 16 Proxy támogatása.

Ha a proxy-support később elérhető, preview alatt kötelező ellenőrizni:
- login;
- logout;
- session fennmaradás;
- cookie frissítés;
- auth callback;
- password-reset redirect.

## Environment változók

Cloudflare build/runtime környezetben szükséges:
- `NEXT_PUBLIC_SUPABASE_URL` – staging Supabase URL;
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` – staging publishable key;
- `SUPABASE_SERVICE_ROLE_KEY` – **secret**, kizárólag Worker/server runtime-ban;
- `SITE_URL` – a Cloudflare preview Worker URL-je.

A valódi értékek nem kerülhetnek repositoryba vagy logba.

A `SITE_URL` miatt a Cloudflare preview URL-t a Supabase Auth engedélyezett redirect URL-jeihez hozzá kell majd adni úgy, hogy a Vercel production redirect továbbra is megmaradjon.

## Adatbiztonság

A kritikus foglalási üzleti logika és ütközésvédelem PostgreSQL/Supabase oldalon marad. A Cloudflare adapter teszt nem módosította:
- az adatbázis-szintű overlap védelmet;
- az RPC jogosultsági ellenőrzéseket;
- a tranzakciókat;
- az auditnaplót;
- a booking concurrency védelmet.

Supabase migráció nem történt.

## Automatikus teszteredmények

Lockolt Cloudflare dependency-k:
- `@opennextjs/cloudflare` 1.20.2;
- `wrangler` 4.125.0;
- pnpm 11 `allowBuilds` csak `esbuild` és `workerd` számára.

A Cloudflare compatibility workflow eredménye:
- frozen dependency install: **PASS**;
- meglévő Vitest: **PASS** — 13 fájl / 67 teszt;
- TypeScript typecheck: **PASS**;
- normál Next.js 16.3.1 production build: **PASS**;
- OpenNext belső Next.js build: **PASS**;
- OpenNext Cloudflare bundle generation: **FAIL — proxy.ts adapter blocker**;
- helyi workerd preview: **NOT RUN**, mert a bundle nem készült el;
- Cloudflare remote preview: **NOT RUN**, mert a build gate nem teljesült.

## Vercel-kompatibilitás

A Cloudflare tesztkonfiguráció mellett a normál `next build` továbbra is sikeres. A Vercel-specifikus konfigurációt és production deploymentet nem módosítottuk.

A branch jelenlegi minimális adapter-fájljai eltávolíthatók anélkül, hogy az alkalmazás üzleti kódját érintenék.

## Cloudflare Workers költségbecslés

A 2026-07-07-én frissített hivatalos Cloudflare pricing szerint a Workers Paid minimum díja **5 USD/hó/account**. Ebben benne van:
- 10 millió Worker request / hónap;
- 30 millió CPU-ms / hónap;
- ezen felül 0,30 USD / további 1 millió request;
- ezen felül 0,02 USD / további 1 millió CPU-ms;
- adatforgalomra/egressre nincs külön Workers díj.

A Cloudflare saját limit-dokumentációja szerint egy átlagos Worker kb. 2,2 ms CPU-t használ requestenként, SSR/auth jellegű nehezebb workload tipikusan 10–20 ms. Az A-Hely kis, belső foglalási alkalmazásának várható forgalma nagyságrendekkel a havi 10 millió request alatt van; még 20 ms CPU/request mellett is kb. 1,5 millió request férne a 30 millió CPU-ms alapkeretbe.

**Költségkövetkeztetés:** a várható A-Hely forgalom mellett nagyon nagy biztonsággal a kb. **5 USD/hó minimum Paid csomagban** maradnánk, feltéve hogy nem vezetünk be nagy forgalmú publikus funkciót vagy indokolatlanul CPU-intenzív SSR-t. A tényleges CPU/request értéket preview/prod monitoringgal később mérni kell.

Paid plan fontos technikai limitek:
- Worker gzip bundle: 10 MB;
- memória: 128 MB/isolate;
- alap HTTP CPU limit 30 s, konfigurálható max. 5 percre;
- 10 000 subrequest/request.

A bundle méretét a jelenlegi proxy-build blokkoló miatt még nem lehetett hitelesen megmérni.

## Jelenlegi minősítés és ajánlás

**Cloudflare technológiailag ígéretes és várhatóan költséghatékony, de a jelenlegi OpenNext + Next.js 16 `proxy.ts` támogatási hiány miatt az A-Hely alkalmazáshoz MOST nem tekinthető biztonságosan deployolhatónak.**

Jelen állapotban az ajánlás:

**maradjunk Vercelen, és tartsuk meg a Cloudflare tesztbranchet / issue-t későbbi újrapróbálásra.**

A Cloudflare-t akkor érdemes újraértékelni, amikor az OpenNext #1277 hivatalosan javítva és kiadott verzióban elérhető. Akkor ugyanazt a CI → OpenNext build → workerd → preview → auth/session/foglalási smoke folyamatot kell végigfuttatni.
