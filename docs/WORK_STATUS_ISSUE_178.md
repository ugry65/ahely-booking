# Folytatási státusz — GitHub #178 admin díjszabás

Utolsó frissítés: 2026-09-23  
Repository: `ugry65/ahely-booking`  
Branch: `feat/178-admin-pricing`  
Base `main`: `953a233d7a1da6eafe243ed9b7e65c367c56bf3b`

## Cél

Az admin központi díjszabásának, userenkénti egyedi óradíjának és foglalásszintű óradíj-felülírásának bevezetése a meglévő pricing- és settlement-adatmodell biztonságos továbbfejlesztésével.

## Elkészült

- Külön admin `Díjszabás` oldal és navigáció.
- Központi sávok: 1–15 óra 2 500 Ft/óra; 15 óra felett–60 óráig 1 900 Ft/óra; 60 óra felett 1 700 Ft/óra.
- Tréningterem csoportos alapdíj: 5 000 Ft/óra.
- User admin adatlap `Díjazás` szakasza, időben verziózott egyedi óradíjjal.
- Admin booking létrehozás/szerkesztés díjelőnézettel, árforrással és foglalásszintű felülírással.
- Prioritás: booking override → user override → központi sáv / Tréningterem.
- Auditált pénzügyi módosítások és jogosultságvédelem.
- Settlement revision és booking line változtathatatlan snapshot; korrekció csak új, indokolt revisionként.
- AllBooked import nem hoz létre foglalásszintű ár-felülírást.
- Üzleti, adatmodell- és architektúra-dokumentáció frissítve.

## Érintett fő fájlok

- `supabase/migrations/20260922160000_admin_pricing_and_booking_rate_override.sql`
- `supabase/tests/database/111_admin_pricing.sql`
- `src/app/(protected)/admin/dijszabas/`
- `src/app/(protected)/admin/felhasznalok/`
- `src/app/(protected)/foglalasok/`
- `src/app/api/admin/pricing/quote/route.ts`
- `docs/ISSUE_178_ADMIN_PRICING_PLAN.md`

## Legutóbbi ellenőrzött állapot

- Alkalmazástesztek: PASS — 28 fájl, 167 teszt.
- TypeScript typecheck: PASS.
- Next.js production build: PASS.
- SQL parser: PASS — 65 statement.
- PL/pgSQL parser: PASS — 17 függvény.
- PostgreSQL pgTAP élő futás: helyben nem elérhető; GitHub Database tests feladata lesz.
- Független security/data-integrity review: elindítva, eredménye feldolgozás alatt.

## Következő lépések

1. Az új atomikus admin booking+díj regressziós tesztek és a teljes ellenőrzési csomag futtatása.
2. Független review megállapításainak javítása.
3. Kis, áttekinthető commitok létrehozása és branch push.
4. PR létrehozása, GitHub Application/Database/Release/Vercel checkek ellenőrzése.
5. Merge csak review és projektgazdai jóváhagyás után.
6. Staging migráció és célzott UAT a merge után; production változtatás külön engedély nélkül tilos.

## Biztonsági korlát

Production adatbázis, konfiguráció, secret és valós production adat nem módosítható külön projektgazdai jóváhagyás nélkül.
