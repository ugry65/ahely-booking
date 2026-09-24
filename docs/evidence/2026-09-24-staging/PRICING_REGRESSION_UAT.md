# Árazási regressziós UAT – staging

Dátum: 2026-09-24  
Környezet: A-Hely staging  
Tesztelő / üzleti elfogadó: projektgazda  
Kapcsolódó main verzió: `1213641387d2244378dfda5971c498861dbc074c` (PR #184 merge)  
Eredmény: **PASS – minden célzott teszt sikeres**

## Hatókör és indok

A PR #179 bevezette az admin díjszabást, userenkénti egyedi óradíjat, foglalásszintű óradíj-felülírást, Tréningterem csoportos díjat és a snapshot-aware havi elszámolási nézeteket. A PR #180–#183 a már létező staging adatbázis migrációs kompatibilitását javította. A PR #184 a staging UAT során talált két regressziót javította:

1. az admin foglalásnál az egyedi óradíj és a felülírás indoka mező nem tartotta meg a begépelt értéket;
2. egy 2026. szeptemberi legacy Tréningterem csoportos foglalás történeti `group_hourly_rate_huf=7500` értéke miatt a havi részletek/összesítés/export hibára futott, mert a booking megelőzte az új `special_room_rates` időszakot.

A javítás a történeti bookingon rögzített 7 500 Ft/óra értéket megőrzi; nem írja visszamenőleg 5 000 Ft-ra és nem hoz létre mesterséges retroaktív tarifát. A tiszta új adatbázis nem kapja vissza a legacy oszlopot.

A korábban elfogadott, e változtatások által nem érintett foglalási UAT-eseteket nem futtattuk újra. A projekt release-evidence szabálya szerint célzott regresszióhoz célzott UAT szükséges.

## Célzott UAT-esetek

| # | Teszt | Elvárt eredmény | Eredmény |
|---|---|---|---|
| 1 | Normál központi díj | Az aktuális havi sáv szerinti központi óradíj jelenik meg | PASS |
| 2 | User egyedi díja | A user fix óradíja felülírja a központi sávot | PASS |
| 3 | Foglalásszintű felülírás | Egyedi óradíj és kötelező indok gépelhető, menthető | PASS |
| 4 | Díjprioritás | booking override → user override → központi / Tréningterem alapdíj | PASS |
| 5 | Tréningterem – egyéni | Normál user/központi díjazás, nem csoportos alapdíj | PASS |
| 6 | Tréningterem – csoportos | 2026.10.01-től 5 000 Ft/óra alapdíj | PASS |
| 7 | Tréningterem + booking override | A foglalásszintű egyedi díj felülírja a csoportos alapdíjat | PASS |
| 8 | Történeti szeptember | A legacy csoportos Tréningterem-foglalás 7 500 Ft/óra marad | PASS |
| 9 | 2026. szeptember havi kimutatás | Összesítés és részletek hiba nélkül betöltődnek | PASS |
| 10 | 2026. október havi kimutatás | Új tarifák szerinti adatok hiba nélkül megjelennek | PASS |
| 11 | Szeptember + október részletes export | Többhavi export elkészül; történeti és új díjak helyesek | PASS |
| 12 | Történeti adatvédelem | Októberi tarifaváltozás nem írja át a szeptemberi pénzügyi történetet | PASS |

## Technikai bizonyíték

A PR #184 előtt stagingen reprodukálható volt a szeptemberi hiba: a havi részletező RPC a legacy Tréningterem-foglalásnál „Nincs érvényes Tréningterem csoportos óradíj” hibával megszakadt. A javítás után stagingen az admin havi summary/details lekérdezések szeptemberre és októberre sikeresen lefutottak, és a szeptemberi legacy tétel 7 500 Ft/óra maradt.

A PR #184 CI kapui a merge előtt PASS állapotúak voltak. A korábbi PR #179 kritikus pricing implementációja külön független review-t és regressziós/concurrency javításokat kapott.

## Elfogadás és határ

**Az árazási változtatási kör staging UAT-ja üzletileg elfogadva.**

Ez az elfogadás nem jelent production deployment engedélyt, production adatbázis-migrációt vagy production booking e-mail `send` mód engedélyt. Production változtatás továbbra is külön projektgazdai jóváhagyáshoz kötött.

A booking e-mail integráció külön release-gate. A stagingen korábban történt valós Resend create/update/cancel PASS, de a normál fejlesztési/UAT üzemmód biztonságosan nem küld valós levelet; a production aktiválás külön döntés.
