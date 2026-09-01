# A-Hely – Production backup restore drill terv és jegyzőkönyv

Dátum: 2026-09-01
Státusz: **TELJES PASS – backupVersion 2 end-to-end restore drill sikeres.**

## Cél

Bizonyítani, hogy a production adatbázisról készült, client-side `age` titkosítású mentés ténylegesen visszaállítható úgy, hogy production és staging adat ne kerüljön veszélybe.

## Biztonsági alapelv

A restore drill kizárólag izolált PostgreSQL 17 / local Supabase környezetben történt. Production vagy staging adatbázisra a drill nem futott.

A recovery private key nem került GitHubba, Google Drive-ra vagy Backblaze B2-re. A visszafejtés azon a helyi gépen történt, ahol a recovery key biztonságosan rendelkezésre áll.

## V1 drill és feltárt hiányosság

Az első production backup:

- GitHub Actions run: `33547980831`
- artifact: `ahely-booking-production_20260901T191321Z_387e40d5afcc.tar.gz.age`
- Google Drive upload/read-back SHA-256: PASS
- Backblaze B2 upload/read-back SHA-256: PASS
- encrypted artifact és belső checksumok: PASS
- business schema/data restore platform-kompatibilis local Supabase stackben: PASS
- kritikus üzleti kontrollszámok: PASS

A v1 restore drill azonban feltárta, hogy a `migration-history.sql` kizárólag data-only dump volt. A production `supabase_migrations.schema_migrations` tábla hat mezőt tartalmazott (`version`, `statements`, `name`, `created_by`, `idempotency_key`, `rollback`), míg a friss local Supabase CLI által létrehozott alapstruktúra csak három mezős volt (`version`, `statements`, `name`). Ezért a migration-history önmagában nem volt önleíró és garantáltan visszaállítható.

## Javítás – backupVersion 2

A backup pipeline javítva lett:

- új `migration-schema.sql` készül a production `supabase_migrations` sémáról;
- `migration-history.sql` külön data-only dump marad;
- `migration-schema.sql` bekerült a nem üres komponens-ellenőrzésbe;
- bekerült a `DATA_SHA256SUMS` és `SHA256SUMS` fájlokba;
- bekerült a `manifest.json` fájllistába és SHA-256 mezővel rendelkezik;
- backup formátum verziója `2`.

## V2 production backup bizonyíték

- GitHub Actions run: `33558905620`
- artifact: `ahely-booking-production_20260901T210519Z_d71300fa8a56.tar.gz.age`
- ugyanazon encrypted artifact Google Drive-ra és Backblaze B2-re feltöltve: PASS
- Google Drive read-back SHA-256: PASS
- Backblaze B2 read-back SHA-256: PASS
- letöltött encrypted artifact `.sha256` sidecar ellenőrzése: PASS
- `age` decrypt: PASS
- tar.gz kicsomagolás: PASS
- minden belső `SHA256SUMS` komponens: PASS, beleértve a `migration-schema.sql` és `migration-history.sql` fájlokat.

## Tiszta end-to-end v2 restore drill

A local Supabase adatbázis nulláról újra lett inicializálva. A korábbi ideiglenes placeholder migration el lett távolítva, majd újabb `supabase db reset --local` futott. A tiszta reset után ugyanabból a v2 artifactból, egy kontrollált tranzakcióban történt a restore:

1. `roles.sql`
2. `schema.sql`
3. `data.sql`
4. a helyi placeholder/meta `supabase_migrations` séma kontrollált cseréje
5. production-kori `supabase_migrations` séma visszaállítása a `migration-schema.sql` fájlból
6. `migration-history.sql` visszatöltése

A restore `ON_ERROR_STOP=1` és tranzakciós/fail-closed módban történt.

### Végső kontrollszámok

A v2 backup és a tiszta v2 restore eredménye pontosan egyezett:

- `auth_users`: 0
- `profiles`: 0
- `rooms`: 11
- `user_room_permissions`: 0
- `booking_series`: 0
- `bookings_total`: 0
- `bookings_active`: 0
- `bookings_cancelled`: 0
- `booking_cancellations`: 0
- `audit_logs`: 0
- `monthly_settlements`: 0
- `settlement_revisions`: 0
- `settlement_booking_lines`: 0
- `migration_history_rows`: 42

A `migration-history.sql` restore során `COPY 42` futott le, az utóellenőrzés pedig szintén 42 sort adott.

## Eredmény

**TELJES PASS.**

Bizonyított, hogy a backupVersion 2 formátum:

- létrejön a production adatbázisból;
- client-side titkosítva ugyanaz az artifact kerül mindkét off-site célra;
- mindkét célhelyen read-back checksum ellenőrizhető;
- a titkosított artifact sértetlensége ellenőrizhető;
- a bundle belső komponensei checksum alapján ellenőrizhetők;
- a business schema és adatok tiszta local Supabase környezetbe visszaállíthatók;
- a kritikus üzleti kontrollszámok egyeznek;
- a production-kori migration-meta séma visszaállítható;
- a migration history teljes egészében visszaállítható és konzisztens.

Megjegyzés: a jelenlegi production adatállapotban a kritikus üzleti kontrollok közül ténylegesen nem nulla adat a `rooms=11`; a felhasználói, foglalási, audit- és settlement kontrollok 0 értékűek voltak. Éles üzleti adatok megjelenése után célszerű ismételt restore drillt végezni nem nulla booking/settlement adatokkal is.

## Kötelező restore sorrend v2 bundle esetén

1. encrypted artifact checksum;
2. decrypt;
3. belső checksumok;
4. platform-kompatibilis izolált local Supabase stack;
5. `roles.sql`;
6. `schema.sql`;
7. `data.sql`;
8. a helyi `supabase_migrations` placeholder/meta séma kontrollált cseréje;
9. `migration-schema.sql`;
10. `migration-history.sql`;
11. kritikus kontrollszámok és migration history ellenőrzése.

## Fontos: a teljes restore PASS nem jelent production GO-t

A backup/restore követelmény ezen része teljesült, de production továbbra is **NEM GO**, amíg a további production-readiness blokkolók nincsenek lezárva, különösen:

- B2 Governance Object Lock 30 nap tényleges konfigurációjának és bizonyításának lezárása;
- `age` recovery private key két független offline/biztonságos megőrzési helyének bizonyítása;
- alert + recovery kontrollált monitoring drill;
- #104 független review lezárása;
- korábban képernyőképen megjelent Google Drive OAuth refresh token rotációja production-ready állapot előtt;
- mobil UAT #98 lezárása;
- teljes staging/UAT és production gate ellenőrzés.
