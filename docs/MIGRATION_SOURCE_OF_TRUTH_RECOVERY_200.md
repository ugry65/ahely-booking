# Migration source-of-truth helyreállítás – #200

## Miért kell
2026-09-25 read-only release audit során kiderült, hogy a main migration könyvtárból hiányzott több, stagingen már alkalmazott történeti migráció. A 20260922160000 admin pricing migráció ezekre az objektumokra épít, ezért a hiányos main lánc productionre nem telepíthető biztonságosan.

## Ebben a branchben visszaemelt kanonikus fájlok
- 202608250001..202608250015: pricing / monthly settlement / payment baseline és hardening
- 202608260001..202608260002: pricing policy + settlement immutability hardening
- 20260826205749: closed settlement line insert protection
- 20260829145720: admin past-booking creation
- 20260830183000: booking update cutoff guard
- 202609040001, 202609050001, 202609050002: first-login/password/admin temporary-password audit hardening

A fájlok nem üzleti logikából lettek újraírva: a korábbi, staginghez használt repository branchek pontos tartalmából kerültek vissza.

## Ismert history-mapping eltérések
A staging Supabase migration history több 2026-08-21/22 migrációt tényleges alkalmazási timestamp-verzióval tart nyilván, míg a main kanonikus fájlnevei logikai verziókat használnak. Ezt nem szabad history-repair nélkül automatikusan productionre/stagingre újrajátszani.

A stagingben továbbá alkalmazva van a preserve_legacy_training_booking_rate változás 20260924080123 history-bejegyzéssel, miközben ennek kanonikus migration fájlja jelenleg nem található a mainen. A staging élő resolve_booking_applied_rate függvényében a legacy group_hourly_rate_huf megőrzési ág jelen van. Ezt külön forward migrationként vissza kell állítani a repó source-of-truth-jába, nem szabad stagingből vakon dumpolni.

## Kötelező további kapuk
1. A hiányzó legacy-training forward migration kanonikus rekonstruálása a jóváhagyott üzleti döntés és staging definíció alapján, teszttel.
2. Teljes migration-chain CI/pristine DB ellenőrzés.
3. Staging/main schema drift audit.
4. Production migration dry-run/plan, production írás nélkül.
5. Kritikus pénzügyi rész független review.
6. Külön owner approval production DB deploy előtt.

Productiont ez a branch nem módosítja.