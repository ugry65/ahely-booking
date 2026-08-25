# Approved UAT UI recovery – 2026-08-25

## Cél
A 2026-08-24-i integrációs UAT során jóváhagyott naptár-felsősáv/foglalási művelet megjelenés megőrzése a jelenlegi `main` kódfa fölött.

## Forrás
- integrációs UAT branch: `uat/phase-prepricing-integration`
- jóváhagyott utolsó head: `69f63e454404454d6e99dbafd1e446c0f526ceaa`
- exact Vercel deployment: `ahely-booking-80lnq0f09-a-hely.vercel.app`

## Visszahozott eltérés
A `CalendarBookingGrid` a kijelölés utáni `Foglalás / Mégse` műveleteket ismét a felső dátum-toolbar `calendar-selection-actions-slot` elemébe rendereli React portalon keresztül.

Ez volt az integrációs UAT-ban jóváhagyott végső működés. A jelenlegi `main` ezt később inline, a naptár alatti action barrá változtatta, miközben a többi UAT CSS/toolbar finomítás megmaradt.

## Biztonság
- recovery branch a jelenlegi `main`-ből indul;
- nincs adatbázis-migráció;
- nincs üzleti logika változás;
- production módosítás nincs;
- merge csak explicit felhasználói jóváhagyással.
