# Approved UAT UI recovery – 2026-08-25

## Cél
A 2026-08-24-i integrációs UAT során jóváhagyott naptár/foglalási felület teljes, vizuálisan elfogadott állapotának megőrzése a jelenlegi `main` kódfa fölött.

## Forrás
- integrációs UAT branch: `uat/phase-prepricing-integration`
- jóváhagyott utolsó head: `69f63e454404454d6e99dbafd1e446c0f526ceaa`
- exact Vercel deployment: `ahely-booking-80lnq0f09-a-hely.vercel.app`

## Visszahozott UI-állapot
A recovery a végső UAT-ból együtt állítja vissza a három, egymással összefüggő naptár-UI fájlt:

- `src/app/(protected)/foglalasok/page.tsx`
- `src/app/(protected)/foglalasok/calendar-booking-grid.tsx`
- `src/app/(protected)/foglalasok/calendar-booking-actions.css`

Ezek együtt adják a jóváhagyott viselkedést és megjelenést, többek között:
- a teljes viewportot kihasználó asztali naptárszélességet;
- a sticky alkalmazásnavigációt és az alatta rögzülő naptár-toolbar-t;
- a kijelölés utáni `Foglalás / Mégse` műveletek felső dátum-toolbar-ba renderelését React portalon keresztül;
- a dátum és a foglalási műveletek közötti végleges térközt/igazítást;
- a mobil nézethez tartozó eltérő sticky viselkedést.

A recovery branch ezen három fájljának blob SHA-ja megegyezik a `69f63e454404454d6e99dbafd1e446c0f526ceaa` UAT head megfelelő fájljaival.

## Biztonság
- recovery branch a jelenlegi `main`-ből indul;
- nincs adatbázis-migráció;
- nincs backend foglalási vagy pénzügyi üzleti logika változás;
- production módosítás nincs;
- merge csak explicit felhasználói jóváhagyással.
