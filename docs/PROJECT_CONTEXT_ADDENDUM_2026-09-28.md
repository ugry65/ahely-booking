# Projektkontextus-kiegészítés – 2026-09-28

Az aktuális projektkontextus mellett a részletes döntési és megvalósítási napló: `docs/SESSION_2026-09-28_CALENDAR_COLOR_AND_SETTLEMENT.md`.

## Tartós döntések
- Saját naptárszín: 20 kontrollált szín, user önkiszolgáló választással; azonos szín több usernél megengedett; productionben kiadva.
- Alkalmi elszámolás: Alkalmi Csoport / Alkalmi Egyéni gyűjtők alatt a `booking_title` szerinti tényleges foglalókat kell hónapon belül összevonni; egyedi alkalmak lenyithatók.
- Fizetettség nem kezelhető egyszerű tartós booleanként; későbbi új foglalás új tartozást képezhet.
- Alkalmi booking-szintű fizetettség/payment allocation még nincs implementálva.
- Fizetési mód és pénz célhelye user-defaultként jelenleg NEM kerül a foglalási rendszerbe; ezt a külön pénzügyi feldolgozó kezeli.
- Production-derived staging csak felvetés; nincs jóváhagyva, production adat stagingbe másolása tilos új döntésig.
- A pénzügyi/elszámolási fejlesztést 2026-09-28-án a projektgazda kérésére megállítottuk.
