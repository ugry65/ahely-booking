# Döntés – foglalási e-mail értesítések alapértelmezett kikapcsolása

**Dátum:** 2026-09-27  
**Kapcsolódó issue:** #239

## Üzleti döntés

Az A-Hely jelenlegi üzleti döntése szerint az automatikus foglalási, foglalásmódosítási és foglalástörlési e-mail értesítések nem szükségesek. Ezeket productionben kikapcsolva tartjuk, amíg valós felhasználói igény nem indokolja a visszakapcsolásukat.

Ez a döntés felülírja a korábbi funkcionális specifikáció azon pontját, amely a foglalási e-mail visszaigazolásokat kötelező MVP-funkcióként írta elő.

## Technikai állapot

- Production: `BOOKING_EMAIL_MODE=disabled`.
- A Vercel nem ütemezi a `/api/internal/booking-email-worker` végpontot.
- A worker és a booking e-mail outbox implementáció megmarad, hogy később kontrolláltan visszakapcsolható legyen.
- A `/api/internal/production-health` cronok változatlanul megmaradnak.
- A Supabase Auth jelszóbeállítási/jelszó-visszaállítási levelei ettől függetlenek, azokat ez a döntés nem kapcsolja ki.

## Visszakapcsolási kapu

A foglalási e-mailek későbbi visszakapcsolása új üzleti döntés. Aktiválás előtt read-only módon ellenőrizni kell a felgyűlt pending/due outbox tételeket és a címzettek körét, mert disabled állapotban is létrejöhetnek outbox tételek. Csak ezután állítható aktív módba a worker és állítható vissza az ütemezés.

## Költség / üzemeltetés

A korábbi percenkénti ütemezés napi 1 440 Vercel cron invocationt okozott projektenként akkor is, ha nem volt kiküldendő foglalási e-mail. A cron eltávolítása ezt a folyamatos, üzletileg jelenleg szükségtelen terhelést megszünteti.
