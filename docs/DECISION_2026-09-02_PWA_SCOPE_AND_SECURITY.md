# Döntés – PWA scope és biztonsági modell

Dátum: 2026-09-02
Kapcsolódó issue: #105

## Döntés

Az A-Hely foglalási rendszer PWA-képességet kap. A PWA a meglévő Next.js webalkalmazás telepíthető megjelenési módja, nem natív mobilalkalmazás és nem külön kódbázis.

## Első verzió scope

- telepíthető iOS / Android / desktop környezetben;
- saját A-Hely név és ikon;
- `standalone` megjelenés;
- online-first működés;
- hálózat nélkül egyértelmű offline fallback;
- nincs offline foglalás, módosítás, törlés, admin vagy pénzügyi művelet;
- nincs background sync üzleti adatírásra.

## Biztonsági döntés

A service worker szándékosan minimális.

Tilos cache-elni:
- authentikált HTML oldalakat;
- Supabase/API válaszokat;
- foglalási adatokat;
- jogosultsági adatokat;
- audit- vagy elszámolási adatokat;
- sessiont, tokent vagy más hitelesítési adatot.

Az első verzió service workere kizárólag az offline fallback oldalt cache-eli. Minden normál hálózati kérés a hálózatra megy. Navigációs hálózati hiba esetén a service worker csak az offline fallback oldalt adja vissza; korábbi foglalási oldal nem jelenhet meg aktuális adatként.

## Frissítés

- új service worker telepítéskor `skipWaiting()`;
- aktiváláskor `clients.claim()`;
- verziózott offline cache;
- aktiváláskor a korábbi A-Hely offline cache-ek törlendők.

## Technikai megoldás

- Next.js `app/manifest.ts` Web App Manifest;
- Next.js `ImageResponse` alapú PWA ikon endpointok;
- explicit `/sw.js` service worker;
- kliensoldali service-worker regisztráció;
- `/offline` fallback oldal;
- nincs külső PWA dependency.

## Elfogadási feltételek

1. Android/Chromium: installálható és standalone módban indul.
2. iOS Safari: Add to Home Screen után helyes név/ikon és standalone megjelenés.
3. Desktop Chromium: installálható.
4. Online baseline működés nem regresszál.
5. Offline állapotban nincs üzleti adatírás.
6. Offline állapotban nincs stale foglalási nézet.
7. Hálózat visszatérésekor friss szerveradat töltődik.
8. `pnpm test`, `pnpm typecheck`, `pnpm build` PASS.
9. Valós mobil PWA UAT szükséges integráció előtt.

## Scope-kapcsolat

A `CURRENT_FUNCTIONAL_BASELINE.md` azon mondata, hogy natív mobilapp nem része az aktív scope-nak, továbbra is igaz. A PWA nem natív alkalmazás; ez a döntés új, explicit aktív scope-kiegészítés.