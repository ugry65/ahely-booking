# Cloudflare Workers / OpenNext kompatibilitási audit

Dátum: 2026-08-22
Branch: `chore/cloudflare-deployment-test`
Issue: #85
PR: #86

## Összefoglaló

A Cloudflare Workers/OpenNext kísérletet a meglévő Vercel production és Supabase backend érintése nélkül végeztük. A standard Next.js alkalmazás buildelhető maradt, de a Cloudflare/OpenNext bundle a Next.js 16 `proxy.ts` adaptertámogatási hiányán blokkolódik. Emiatt remote Cloudflare previewt és auth/session smoke tesztet biztonságosan nem indítunk.

**Jelenlegi minősítés: részben kompatibilis, de jelenleg nem deployolható biztonságosan Cloudflare Workersre.**

**Ajánlás: most maradjunk Vercelen; a Cloudflare tesztet az OpenNext #1277 hivatalos javítása után ismételjük meg.**

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

Lockolt verziók:
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

A kompatibilitási build OpenNext 1.20.2 + Next.js 16.3.1 kombinációnál elbukik. A normál Next.js build sikeres, majd az OpenNext bundle-generálás ezt a hibát adja:

```text
Error: This error should only happen for static 404 and 500 page from page router.
File server/middleware.js does not exist
```

A hiba a `@opennextjs/aws` `copyTracedFiles` / OpenNext Cloudflare bundle-generálási útvonalán történik, közvetlenül a middleware/proxy bundle készítésekor.

Ez összhangban áll az OpenNext jelenleg nyitott #1277 hibájával: a Next.js 16 `proxy.ts` Node.js middleware/proxy konvenció Cloudflare Workers támogatása még nincs kész. A #1279 ugyanezt a hiányzó támogatást írja le, és #1277 duplikátumaként zárták.

### Miért blokkoló az A-Hely számára?

A `proxy.ts` a Supabase session frissítés és a védett route-ok korai auth kezelésének része. A Next.js 16 dokumentációban a Proxy a jelenlegi szabványos mechanizmus az ilyen request-előtti auth/routing logikára.

Nem fogadható el olyan workaround, amely:
- eltávolítja a proxyt;
- kikapcsolja a session-frissítést;
- gyengíti a védett route-ok auth ellenőrzését;
- OpenNext belső bundle-fájljait saját patch-csel módosítja;
- Cloudflare-specifikus auth-elágazást épít az alkalmazásba.

### Lehetséges utak

1. **Várni az OpenNext hivatalos `proxy.ts` támogatására — ajánlott.**
   - nincs alkalmazáskód-változás;
   - nincs auth regresszió;
   - minimális vendor lock-in;
   - később ugyanazon kísérlet friss adapterrel megismételhető.

2. **Next.js 15 Maintenance LTS-re visszalépni és régi middleware-modellt használni.**
   - lehetséges alternatíva;
   - framework-szintű visszalépés;
   - jelen kísérlethez aránytalan és külön architekturális döntést igényelne.

3. **OpenNext saját/PR patch használata.**
   - magas vendor-lock-in és karbantartási kockázat;
   - auth/security szempontból érzékeny build-runtime patch;
   - nem javasolt.

## Node.js-specifikus API / filesystem

A repository audit során nem találtunk alkalmazáskódban:
- `node:` importot;
- `fs` filesystem használatot;
- lokális tartós fájlrendszerre támaszkodó üzleti logikát.

## Server Actions és Route Handlers

Az alkalmazás több `"use server"` actiont használ. Auth callback és admin CSV route handlerek is vannak. A normál Next.js build és az OpenNext belső Next-build fázisa ezeket sikeresen fordította. Runtime smoke a proxy bundle-blokkoló miatt még nem volt lehetséges.

## Supabase SSR / Auth / cookie

A `src/lib/supabase/server.ts` a `cookies()` Next API-t és az `@supabase/ssr` cookie adaptert használja. A proxy ugyanezt a session modellt követi request/response cookie-kkal.

Nem találtunk Vercel-specifikus auth API-t. Maga a Supabase SSR réteg nem azonosított inkompatibilitási ok; a blokkoló az adapter Next.js 16 Proxy támogatása.

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

Valódi érték nem került repositoryba vagy logba.

A későbbi Cloudflare preview URL-t a Supabase Auth engedélyezett redirect URL-jeihez hozzá kell adni úgy, hogy a Vercel production redirect továbbra is megmaradjon.

## Adatbiztonság

A hosting-kísérlet nem módosította a Supabase adatmodellt vagy üzleti logikát. Változatlan maradt:
- adatbázis-szintű overlap védelem;
- RPC jogosultsági ellenőrzés;
- tranzakcióbiztonság;
- auditnapló;
- booking concurrency védelem.

Supabase migráció nem történt.

## Kódmódosítások

Csak a tesztbranchben:
- `package.json` – OpenNext/Wrangler dependency és Cloudflare build/preview/deploy scriptek;
- `pnpm-lock.yaml` – lockolt dependency-k;
- `pnpm-workspace.yaml` – pnpm 11 explicit build allowlist csak `esbuild` és `workerd` számára;
- `wrangler.jsonc` – minimális Workers konfiguráció `nodejs_compat` flaggel;
- `open-next.config.ts` – alap `defineCloudflareConfig()` adapter config;
- `.gitignore` – `.open-next`, `.wrangler`, `.dev.vars` kizárása;
- `.github/workflows/cloudflare-compatibility.yml` – reprodukálható kompatibilitási pipeline;
- jelen audit dokumentum.

Alkalmazás üzleti kód nem változott.

## Automatikus teszteredmények

- frozen dependency install: **PASS**;
- meglévő Vitest: **PASS** — 13 fájl / 67 teszt;
- TypeScript typecheck: **PASS**;
- normál Next.js 16.3.1 production build: **PASS**;
- OpenNext belső Next.js build: **PASS**;
- OpenNext Cloudflare bundle generation: **FAIL — proxy.ts adapter blocker**;
- helyi workerd preview: **NOT RUN**, mert a bundle nem készült el;
- Cloudflare remote preview: **NOT RUN**, mert a build gate nem teljesült;
- funkcionális Cloudflare auth/booking smoke: **NOT RUN**, mert nincs biztonságos deployolható bundle.

## Vercel-kompatibilitás

A Cloudflare tesztkonfiguráció mellett a normál `next build` sikeres. A Vercel production konfigurációt/deploymentet nem módosítottuk. A Cloudflare adapterfájlok eltávolíthatók az alkalmazás üzleti kódjának érintése nélkül.

## Cloudflare Workers költségbecslés

A 2026-07-07-én frissített hivatalos Cloudflare pricing szerint a Workers Paid minimum díja **5 USD/hó/account**. Tartalmaz:
- 10 millió Worker request / hónap;
- 30 millió CPU-ms / hónap;
- többlet: 0,30 USD / további 1 millió request;
- többlet: 0,02 USD / további 1 millió CPU-ms;
- Workers egress/bandwidth külön díj nélkül.

A hivatalos limit-dokumentáció szerint az átlagos Worker kb. 2,2 ms CPU/request, SSR/auth jellegű nehezebb workload tipikusan 10–20 ms. Az A-Hely várható belső forgalma nagyságrendekkel a havi 10 millió request alatt van. Még 20 ms CPU/request mellett is kb. 1,5 millió request fér a 30 millió CPU-ms alapkeretbe.

**Költségkövetkeztetés:** a várható A-Hely forgalom mellett nagy biztonsággal a kb. **5 USD/hó minimum Paid csomagban** maradnánk. Ezt tényleges CPU/request mérésnek kell majd megerősítenie, amikor működő preview elérhető.

Paid plan releváns technikai limitek:
- Worker gzip bundle: 10 MB;
- memória: 128 MB/isolate;
- alap HTTP CPU limit 30 s, max. 5 percre emelhető;
- 10 000 subrequest/request.

A bundle méretét a proxy-build blokkoló miatt még nem lehetett hitelesen megmérni.

## Végső jelenlegi ajánlás

**maradjunk Vercelen** — jelenleg.

Nem azért, mert a teljes A-Hely architektúra Cloudflare-alkalmatlan, hanem mert az aktuális hivatalos OpenNext adapter még nem támogatja biztonságosan azt a Next.js 16 `proxy.ts` mechanizmust, amelyre az auth/session rétegünk épül.

A Cloudflare újrapróbálásának triggerfeltétele: OpenNext #1277 javítása megjelenik hivatalos kiadott adapterverzióban. Ekkor újra kell futtatni: dependency install → tests → typecheck → Next build → OpenNext build → workerd smoke → Cloudflare preview → staging Supabase auth/session/foglalás smoke → Vercel regresszióellenőrzés.

## Stop gate

A kísérlet ennél a pontnál szándékosan megáll. Nem végzünk framework-downgrade-ot, auth/proxy átírást vagy OpenNext belső patch-elést felhasználói architekturális döntés nélkül.
