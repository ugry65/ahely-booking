# Booking e-mail production szolgáltatási döntés — 2026-09-30

A projektgazda 2026-09-30-án megerősítette: a foglalási értesítő e-mailek küldése jelenleg tudatosan ki van kapcsolva. A jóváhagyott production állapot `BOOKING_EMAIL_MODE=disabled`; a booking e-mail küldés nem része a jelenlegi production szolgáltatásnak. Az Auth e-mailek ettől függetlenek.

Ez üzleti döntés, **nem az éles Vercel-változó értékének leolvasása**. A release előtt külön, read-only módon kell igazolni az adott production deployment tényleges `BOOKING_EMAIL_MODE` értékét, és a megfigyelés bizonyítékát, projektazonosítóját, deployment ID-ját és időpontját rögzíteni. Hiányzó vagy eltérő megfigyelésnél a kiadási kapu zárva marad.

Az e-mail szolgáltatás későbbi `capture` vagy `send` aktiválása külön projektgazdai döntést és az összes, `docs/release-evidence.json` fájlban megőrzött activation check bizonyított lezárását igényli. A jelen döntés nem engedélyezi sem a booking e-mail küldést, sem production adatbázis-migrációt. A korábbi #176 bridge-warning PR merge-je a Git historyban igazolható; a független review külön, hiteles bizonyítékának hiányát nem tekintjük lezártnak.
