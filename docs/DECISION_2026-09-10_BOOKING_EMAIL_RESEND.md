# Foglalási e-mail szolgáltató – Resend döntés

Állapot: **jóváhagyott üzleti/technikai döntés**

Dátum: 2026-09-10

Kapcsolódó: #107, PR #111

## Döntés

A foglalási értesítések küldéséhez a staging és production SMTP szolgáltató **Resend**.

Ez felülírja a 2026-09-03-i MediaCenter SMTP szolgáltatói irányt. A transactional outbox, worker, retry/dead-letter, audit és deduplikációs architektúra változatlan marad; csak a küldő SMTP végpont és hitelesítés változik.

## Nem titkos konfiguráció

- `SMTP_HOST=smtp.resend.com`
- `SMTP_PORT=465`
- `SMTP_SECURE=true`
- `SMTP_USER=resend`
- `BOOKING_EMAIL_FROM=A-Hely Foglalás <foglalas@a-hely.com>`
- `BOOKING_EMAIL_REPLY_TO=foglalas@a-hely.com`
- `BOOKING_EMAIL_MESSAGE_ID_DOMAIN=a-hely.com`

Az `SMTP_PASS` a Resend titkos credentialje, kizárólag környezeti secretként tárolható; repositoryba, dokumentációba vagy logba nem kerülhet.

## Kötelező staging UAT production előtt

Valós Resend küldéssel ellenőrizendő create/update/cancel, admin owner-routing, recurring scope-ok, duplikációmentesség, delivery audit, valamint kontrollált retry/dead-letter viselkedés.

## Production kapu

A `BOOKING_EMAIL_MODE=send` production aktiválása csak sikeres staging Resend UAT, zöld CI és külön production release-jóváhagyás után történhet.
