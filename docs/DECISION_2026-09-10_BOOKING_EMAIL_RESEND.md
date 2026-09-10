# Foglalási e-mail szolgáltató – Resend döntés

Állapot: **jóváhagyott üzleti/technikai döntés**

Dátum: 2026-09-10

Kapcsolódó: #107, PR #111

## Döntés

A foglalási értesítések küldéséhez a production és staging SMTP szolgáltató **Resend**.

Ez felülírja a 2026-09-03-i MediaCenter SMTP szolgáltatói irányt. A transactional outbox, worker, retry/dead-letter, audit és deduplikációs architektúra változatlan marad; csak a küldő SMTP végpont és hitelesítés változik.

## Nem titkos konfiguráció

- `SMTP_HOST=smtp.resend.com`
- `SMTP_PORT=465`
- `SMTP_SECURE=true`
- `SMTP_USER=resend`
- `BOOKING_EMAIL_FROM=A-Hely Foglalás <foglalas@a-hely.com>`
- `BOOKING_EMAIL_REPLY_TO=foglalas@a-hely.com`
- `BOOKING_EMAIL_MESSAGE_ID_DOMAIN=a-hely.com`

Az `SMTP_PASS` a Resendhez tartozó titkos API key / SMTP credential, kizárólag Vercel/GitHub környezeti secretként tárolható; repositoryba, dokumentációba vagy logba nem kerülhet.

## Indoklás

- az `a-hely.com` domain és a `foglalas@a-hely.com` feladó már működőképes Resenddel;
- a MediaCenter SMTP-val korábban reprodukálható kapcsolati/SMTP problémák jelentkeztek;
- egyetlen e-mail szolgáltató csökkenti az üzemeltetési bizonytalanságot és a konfigurációs eltérést;
- a meglévő worker szolgáltatófüggetlen `SMTP_*` környezeti változókat használ, ezért az átállás nem igényel booking/outbox adatmodell-változást.

## Kötelező staging UAT production aktiválás előtt

1. valós Resend levél booking create eseményre;
2. valós levél booking update eseményre;
3. valós levél booking cancel eseményre;
4. admin által user nevében végzett create/update/cancel – mindig a booking owner kapja;
5. sorozat/occurrence/following/series összefoglaló viselkedés ellenőrzése;
6. címzett, feladó, Reply-To, dátum/idő (`Europe/Budapest`) és tartalom ellenőrzése;
7. ugyanazon üzleti műveletből nincs duplikált levél;
8. delivery attempt / worker run audit és admin monitor egyezik;
9. retry/dead-letter viselkedés kontrollált hibával ellenőrzött;
10. secret, provider nyers válasz vagy érzékeny payload nem szivárog UI-ba/logba.

## Production kapu

A `BOOKING_EMAIL_MODE=send` production aktiválása csak sikeres staging Resend UAT, zöld CI és külön production release-jóváhagyás után történhet.
