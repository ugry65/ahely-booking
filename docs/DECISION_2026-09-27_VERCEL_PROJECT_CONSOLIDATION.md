# Döntés – Vercel projektkonszolidáció

**Dátum:** 2026-09-27

## Döntés

Az A-Hely foglalási rendszer aktív Vercel topológiája két projektből áll:

- **Production:** `ahely-booking` (`prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo`)
- **Staging:** `ahely-booking-staging-web` (`prj_LzVgZgZBCAj4zA64YoYED3XkLGKW`)

Az alábbi két örökölt/felesleges projektet véglegesen ki kell vezetni és törölni:

- `ahely-booking-kveb` (`prj_uXMas7ycAF8KVFQ0o69mzFSWhHMF`)
- `ahely-booking-541h` (`prj_4Fy1hF50tzy8f2VzvejP4trNsWof`)

## Indoklás

A read-only Vercel ellenőrzés 2026-09-27-én igazolta, hogy mindkét felesleges projekt ugyanabból a `ugry65/ahely-booking` GitHub repositoryból automatikusan deploymenteket készít. A #239 fejlesztési branch minden commitja külön deploymentet indított mindkét projekten. Ezek a projektek nem részei a kívánt staging/production architektúrának, ezért szükségtelen build- és infrastruktúra-fogyasztást okoznak.

## Biztonsági korlát

A törlés kizárólag a fenti két projektet érintheti. Tilos törölni vagy módosítani:

- `ahely-booking` – production;
- `ahely-booking-staging-web` – staging.

A projektkonszolidáció nem adatbázis-migráció és nem jogosít fel Supabase projekt, production adat, domain vagy Auth konfiguráció törlésére/módosítására.

## Elvárt végállapot

A Vercel team alatt az A-Hely foglalási rendszerhez csak a production és staging projektek maradnak aktívak. Fejlesztési commitok ne generáljanak deploymentet a két megszüntetett legacy projektben.

## Kapcsolódó release-kockázat

A különálló production projekt automatikus `main` deploymentjének korábban feltárt problémája ettől független. A két legacy projekt törlése csökkenti a fölös deploymenteket, de **nem oldja meg önmagában** a production release-isolációt. Annak külön rendezése továbbra is szükséges.
