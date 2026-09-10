# Booking e-mail – Resend staging UAT

Állapot: előkészítve, production aktiválás előtt kötelező.

Kapcsolódó: #107, PR #111, `DECISION_2026-09-10_BOOKING_EMAIL_RESEND.md`.

## Előfeltételek

A staging Vercel környezetben kizárólag secretként / environment variable-ként:

- `BOOKING_EMAIL_MODE=send`
- `SMTP_HOST=smtp.resend.com`
- `SMTP_PORT=465`
- `SMTP_SECURE=true`
- `SMTP_USER=resend`
- `SMTP_PASS=<Resend secret>`
- `BOOKING_EMAIL_FROM=A-Hely Foglalás <foglalas@a-hely.com>`
- `BOOKING_EMAIL_REPLY_TO=foglalas@a-hely.com`
- `BOOKING_EMAIL_MESSAGE_ID_DOMAIN=a-hely.com`
- érvényes `CRON_SECRET`

Secret érték nem kerülhet issue-ba, logba vagy képernyőképbe.

## Kötelező UAT esetek

1. user create → 1 valós levél;
2. user update → 1 valós levél;
3. user cancel → 1 valós levél;
4. admin create/update/cancel más user nevében → mindig a booking owner kapja;
5. recurring create → 1 összefoglaló levél;
6. occurrence update/cancel → 1 levél;
7. following update/cancel → 1 összefoglaló levél;
8. series update/cancel → 1 összefoglaló levél;
9. ugyanazon idempotens művelet újrafuttatása → nincs duplikált levél;
10. hibás/átmenetileg elérhetetlen transport → booking megmarad, outbox retry/dead-letter állapot és audit helyes.

## Ellenőrzendő levéltartalom

- címzett;
- feladó és Reply-To;
- eseménytípus;
- helyiség;
- dátum és kezdés/befejezés Europe/Budapest szerint;
- használat típusa / cím, ha releváns;
- adminművelet jelzése;
- sorozat scope és összefoglaló adatok;
- nincs secret, auth token, technikai stack vagy belső audit payload.

## Reconciliation

UAT után az admin e-mail monitorban és adatbázisban egyezzen:

- outbox darabszám;
- `sent` / `retry` / `dead_letter` státusz;
- delivery attempt darabszám;
- worker run összesítő;
- nincs duplikált `provider_message_id` ugyanazon logikai művelethez;
- nincs függő stale lease.

## Production kapu

Production `BOOKING_EMAIL_MODE=send` csak akkor engedhető, ha minden kötelező UAT PASS, CI zöld, a scheduler/worker elérési út stabil, és a tulajdonos külön jóváhagyja a production aktiválást.
