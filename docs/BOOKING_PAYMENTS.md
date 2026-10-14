# Foglaláshoz kapcsolt befizetések

2026-10-14. Követelmény és staging-megvalósítás. Production GO nincs.

Imre jóváhagyott igénye: alapból nem fizetett foglalások, csak admin által
rögzíthető befizetés, havi részfizetés/teljes fizetés kimutatása. Az összeg
nyilvántartása szükséges a változó havi díjsáv és a részfizetés miatt.

## Használat

- Napi naptár → foglalás → **Befizetések**, kizárólag adminnak.
- Admin → Havi órák és elszámolás → tételes sor → **Befizetések**;
  mobilon ugyanitt a kártyán elérhető.
- Átvett összeg, dátum, fizetési mód, célhely és opcionális megjegyzés.
- Alapérték készpénz, célhely készpénz. A rendszer nem indít banki műveletet.
- Részfizetés több befizetési rekorddal rögzíthető.
- Téves rögzítés indoklással/megerősítéssel érvényteleníthető, nem törölhető.
  Ez nem tényleges pénzvisszafizetés. Javítást új, helyes rögzítés követhet.
- Havi befizetési összesítés: havi díj, befizetve, fennmaradó, túlfizetés,
  fizetési állapot. Nyitott hónapban előzetes; lezárt hónapban snapshot díj.
- Összesítő CSV/Excel és részletes CSV pénzügyi oszlopokkal bővül.
  A korábbi revision/elszámolási állapot exportoszlopok nem térnek vissza.

## Adatmodell és védelem

Egy befizetés egy `payments` rekord; opcionális `booking_id` kapcsolja
az alkalomhoz. A korábbi havi befizetések is beleszámítanak, duplázás nélkül.
`payment_voids` append-only érvénytelenítési napló. Csak aktív admin RPC-k,
üres search_path, explicit ACL, RLS és közvetlen kliensírás-tiltás.
Idempotenciakulcs/payload-ellenőrzés, user/hónap tranzakciós zárolás és audit.
Lezárt revision és foglalási díjszabás nem változik a pénz rögzítésétől.

A lemondás nem törli az átvett pénzt: havi jóváírás/túlfizetésként megmarad.
Érvényes befizetéssel a foglaló vagy az elszámolási hónap nem cserélhető
észrevétlenül; külön pénzrendezés szükséges. Duplikált foglalás nem örököl pénzt.
Ismétlődő foglalásnál a befizetés mindig az egyetlen kiválasztott alkalomé.

Az alkalmi gyűjtőfiókok havi összesített egyenlege fiókszintű; az egyedi
alkalmak befizetése a foglalási oldalon és a részletes CSV-ben követhető.
Korábbi befizetés nélküli adatokat nem jelölünk utólag fizetettnek.
Számlázás/kiküldés és a felhasználói végleges havi kártya most nem változik.

## Ellenőrzés és kiadás

Helyi typecheck és Vitest első futás: PASS, 305 teszt. Új pgTAP-regresszió
és független review folyamatban; staging DB migráció még nincs alkalmazva.
A pénzügyi írást csak a végleges jelölt CI/review PASS után telepítjük.
Staging: `fvwapntzhavhgazeflri`, web: ahely-booking-staging-web.
Production adatbázis/ág/konfiguráció módosítása tilos külön jóváhagyás nélkül.
