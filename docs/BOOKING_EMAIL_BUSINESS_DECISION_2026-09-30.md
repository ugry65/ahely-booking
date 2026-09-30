# Booking e-mail production szolgáltatási döntés — 2026-09-30

A projektgazda 2026-09-30-án megerősítette: a foglalási értesítő e-mailek küldése jelenleg tudatosan ki van kapcsolva. A jóváhagyott production állapot `BOOKING_EMAIL_MODE=disabled`; a booking e-mail küldés nem része a jelenlegi production szolgáltatásnak. Az Auth e-mailek ettől függetlenek.

Ez üzleti döntés, **nem az éles Vercel-változó értékének leolvasása**. Amíg a jóváhagyott production mód `disabled`, az általános alkalmazás-release nem függ külön Vercel API-s runtime bizonyítéktól: a kikapcsolt booking e-mail nem önálló release-kapu. A `capture` vagy `send` aktiválás viszont továbbra is csak külön, read-only production runtime bizonyítékkal és az activation checkek lezárásával engedhető.

Az e-mail szolgáltatás későbbi `capture` vagy `send` aktiválása külön projektgazdai döntést és az összes, `docs/release-evidence.json` fájlban megőrzött activation check bizonyított lezárását igényli. A jelen döntés nem engedélyezi sem a booking e-mail küldést, sem production adatbázis-migrációt. A korábbi #176 bridge-warning PR merge-je a Git historyban igazolható; a független review külön, hiteles bizonyítékának hiányát nem tekintjük lezártnak.
