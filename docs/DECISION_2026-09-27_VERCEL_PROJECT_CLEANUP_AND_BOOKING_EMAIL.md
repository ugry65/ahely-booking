# Döntési jegyzőkönyv – Vercel projekt-tisztítás és booking e-mail ütemezés

Dátum: 2026-09-27

## Cél
A 2026-09-27-én meghozott és részben már végrehajtott üzemeltetési döntések tartós rögzítése.

## Végrehajtott döntések

### Két felesleges Vercel projekt törlése
A projektgazda törölte:
- `ahely-booking-kveb` – korábbi ID: `prj_uXMas7ycAF8KVFQ0o69mzFSWhHMF`
- `ahely-booking-541h` – korábbi ID: `prj_4Fy1hF50tzy8f2VzvejP4trNsWof`

A törlés előtti vizsgálat szerint mindkettő ugyanabból a GitHub repo/main ágból kapott deploymenteket. Runtime logjaikban a booking-email worker percenként futott, de `cron_secret` konfigurációs hibával 503-at adott; a vizsgált állapotban nem küldött booking e-maileket.

Aktív Vercel projektek:
- staging: `ahely-booking-staging-web`
- production: `ahely-booking`

### Booking értesítő e-mailek kikapcsolása
Üzleti döntés: az automatikus foglalási értesítő e-maileket egyelőre nem használjuk. Csak valós felhasználói igény esetén vizsgáljuk újra az aktiválásukat.

Ez NEM érinti a Supabase Auth jelszó-reset, aktiváló és egyéb hitelesítési e-mailjeit.

Production célállapot: `BOOKING_EMAIL_MODE=disabled`.

A booking-email worker kódja megmarad, de automatikusan ne fusson.

### Percenkénti booking-email cron eltávolítása
A `vercel.json` korábban percenként futtatta a `/api/internal/booking-email-worker` végpontot. Ezt el kell távolítani, mert kikapcsolt booking e-mail mellett felesleges háttérterhelés és költség.

A production-health cronok ettől függetlenek, azokat meg kell tartani.

Kapcsolódó fejlesztés: issue #239 / PR #240. Csak zöld CI és review után merge-elhető.

### Staging cronok kikapcsolása
A projektgazda 2026-09-27-én a `ahely-booking-staging-web` Vercel projektben a Cron Jobs funkciót kikapcsolta.

Indok: stagingben nincs szükség folyamatos percenkénti booking-email workerre, és staging ne fogyasszon állandó erőforrást ilyen háttérfeladatra.

A projekt-szintű kapcsoló a staging production-health cronokat is leállítja. Ez jelenleg elfogadott staging állapot; kontrollált teszthez később visszakapcsolható.

### Production cron állapot
2026-09-27-én a production Vercel projektben is történt projekt-szintű cron-kikapcsolás a booking-email leállításának részeként. Ez minden production cront érint.

A végleges cél: a repositoryból kikerül a booking-email cron, a production-health cronok megmaradnak. A production cron funkció újbóli engedélyezése előtt ellenőrizni kell, hogy a deployolt `vercel.json` már nem tartalmaz booking-email worker ütemezést.

## Nyitott release-architektúra feladat
Kiderült, hogy staging és production Vercel is a GitHub `main` ághoz kapcsolódik, ezért main merge production deploymentet is kiválthat. Ez ellentétes az elfogadott folyamattal.

Cél:
`feature → PR/CI → main → automatikus staging → staging UAT → explicit emberi production-jóváhagyás → production deploy`

Amíg a production automatikus Git-deploymentje nincs biztonságosan leválasztva, új fejlesztést nem szabad rutinból mainbe merge-elni.

A staging/production release-viselkedést nem szabad a közös `vercel.json` segítségével szétválasztani; projekt-specifikus Vercel/GitHub release-kapu szükséges.

## Tartós üzemeltetési szabályok
- Staging ne fusson folyamatosan olyan háttérfeladattal, amelyre nincs aktív tesztelési igény.
- Productionben csak üzletileg szükséges háttérfolyamat fusson.
- Booking e-mail visszakapcsolása külön döntés, staging UAT és explicit production jóváhagyás után történhet.
- Auth/jelszó-reset e-mail külön rendszer, nem függ a booking-email workertől.
- Production adatbázis-, environment-, deployment- és monitoring-változtatás explicit projektgazdai jóváhagyást igényel.
