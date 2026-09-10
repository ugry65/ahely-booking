# Booking e-mail – Resend staging UAT

Kapcsolódó: #107, PR #111, `DECISION_2026-09-10_BOOKING_EMAIL_RESEND.md`.

## Előfeltételek

Staging runtime:
- `BOOKING_EMAIL_MODE=send`
- `SMTP_HOST=smtp.resend.com`
- `SMTP_PORT=465`
- `SMTP_SECURE=true`
- `SMTP_USER=resend`
- `SMTP_PASS=<secret>`
- `BOOKING_EMAIL_FROM=A-Hely Foglalás <foglalas@a-hely.com>`
- `BOOKING_EMAIL_REPLY_TO=foglalas@a-hely.com`
- érvényes `CRON_SECRET`

Secret érték nem kerülhet issue-ba, logba vagy képernyőképbe.

## Kötelező UAT

1. user create → 1 valós levél;
2. user update → 1 valós levél;
3. user cancel → 1 valós levél;
4. admin create/update/cancel más user nevében → a booking owner kapja;
5. recurring create → 1 összefoglaló levél;
6. occurrence/following/series update és cancel → scope-onként 1 megfelelő levél;
7. idempotens ismétlés → nincs duplikált levél;
8. kontrollált transport hiba → booking megmarad, retry/dead-letter és audit helyes.

## Ellenőrzés

Címzett, From, Reply-To, eseménytípus, helyiség, Europe/Budapest dátum/idő, adminjelzés és recurring összefoglaló legyen helyes. Secret, token, stack trace vagy belső audit payload ne jelenjen meg.

Az admin e-mail monitor és az adatbázis outbox/delivery-attempt/worker-run adatai egyezzenek; ne maradjon stale lease vagy duplikált logikai küldés.

## Production kapu

Production `BOOKING_EMAIL_MODE=send` csak teljes staging PASS, zöld CI, működő scheduler/worker és külön tulajdonosi jóváhagyás után engedhető.
