# A-Hely – Production backup restore drill terv és jegyzőkönyv

Dátum: 2026-09-01
Státusz: **részleges PASS, egy feltárt backup-formátum hiányosság javítva; v2 bundle újraellenőrzése szükséges a teljes PASS-hoz.**

## Cél

Bizonyítani, hogy a production adatbázisról készült, client-side `age` titkosítású mentés ténylegesen visszaállítható úgy, hogy production és staging adat ne kerüljön veszélybe.

## Biztonsági alapelv

A restore drill kizárólag izolált PostgreSQL 17 / local Supabase környezetben történhet. Production vagy staging adatbázisra a drill nem futtatható.

A recovery private key nem kerül GitHubba, Google Drive-ra vagy Backblaze B2-re. A visszafejtés azon a helyi gépen történik, ahol a recovery key biztonságosan rendelkezésre áll.

## Első forrásbackup és dual-target bizonyíték

- GitHub Actions run: `33547980831`
- artifact: `ahely-booking-production_20260901T191321Z_387e40d5afcc.tar.gz.age`
- Supabase/PostgreSQL dump image: `ghcr.io/supabase/postgres:17.6.1.165`
- Google Drive feltöltés és read-back SHA-256 ellenőrzés: PASS
- Backblaze B2 feltöltés és read-back SHA-256 ellenőrzés: PASS

Az első, v1 backup bundle tartalma:

- `roles.sql`
- `schema.sql`
- `data.sql`
- `migration-history.sql`
- `control-counts.json`
- `manifest.json`
- `DATA_SHA256SUMS`
- `SHA256SUMS`

## 2026-09-01 tényleges restore drill – végrehajtott lépések

1. A titkosított artifact letöltése Google Drive-ról: PASS.
2. A `.sha256` sidecar és a letöltött encrypted artifact összevetése: PASS.
3. `age` visszafejtés a helyi recovery private key-jel: PASS.
4. Tar.gz kicsomagolás: PASS.
5. Minden belső `SHA256SUMS` ellenőrzése: PASS.
6. Első egyszerű PostgreSQL/Supabase Postgres próbák tranzakciósan, hiba esetén teljes rollbackkel: fail-closed működés bizonyítva.
7. Teljes Supabase local stack indítása Supabase CLI 2.116.0-val, PostgreSQL image `ghcr.io/supabase/postgres:17.6.1.165`: PASS.
8. `roles.sql + schema.sql + data.sql` restore egy tranzakcióban a platform-kompatibilis local stackbe: PASS.
9. Kritikus üzleti/adat kontrollszámok összevetése a `control-counts.json` értékeivel: PASS.

### Restore utáni kontrollszámok

A backup és a restore eredménye pontosan egyezett:

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

A séma visszaállt és a kritikus üzleti táblák lekérdezhetők voltak. A `public.rooms` restore utáni értéke 11, pontosan a backup kontrollértékével egyezően.

## Drill során feltárt valós backup-formátum hiányosság

A `migration-history.sql` v1-ben kizárólag `--data-only --schema supabase_migrations` dump volt. A production `supabase_migrations.schema_migrations` tábla hat mezőt tartalmazó history adatot adott:

- `version`
- `statements`
- `name`
- `created_by`
- `idempotency_key`
- `rollback`

Ezzel szemben egy friss local Supabase CLI által inicializált migration-history tábla csak a saját aktuális alapstruktúráját hozta létre (`version`, `statements`, `name`). Emiatt a migration history adat önmagában nem önleíró és nem garantáltan restore-olható egy későbbi/eltérő CLI-verzió által létrehozott meta-sémába.

Ez a restore drill lényegi eredménye: a v1 backup üzleti séma- és adatrestore-ja működik, de a migration-history teljes visszaállíthatóságához a production `supabase_migrations` séma definícióját is a backupnak kell hordoznia.

## Javítás – backupVersion 2

A `scripts/backup-production.sh` javítva lett:

- új `migration-schema.sql` készül a production `supabase_migrations` sémáról;
- a meglévő `migration-history.sql` továbbra is külön data-only dump;
- `migration-schema.sql` bekerült a nem üres komponens-ellenőrzésbe;
- bekerült a `DATA_SHA256SUMS` és `SHA256SUMS` fájlokba;
- bekerült a `manifest.json` fájllistába és SHA-256 mezővel rendelkezik;
- backup formátum verziója `2`.

A cél az, hogy a restore ne a local/future CLI által létrehozott migration-meta struktúrától függjön, hanem a backup saját production-kori meta-sémáját állítsa vissza.

## Kötelező restore sorrend v2 bundle esetén

1. encrypted artifact checksum;
2. decrypt;
3. belső checksumok;
4. platform-kompatibilis izolált local Supabase stack;
5. `roles.sql`;
6. `schema.sql`;
7. `data.sql`;
8. `migration-schema.sql`;
9. `migration-history.sql`;
10. kritikus kontrollszámok és migration history ellenőrzése.

Minden adatbázis-restore lépés `ON_ERROR_STOP=1` és tranzakciós/fail-closed módon történjen, ahol technikailag alkalmazható.

## Teljes PASS feltétele

A drill csak akkor kap teljes PASS státuszt, ha egy új **backupVersion 2** production artifacttal:

- a dual-target upload/read-back checksum PASS;
- encrypted és belső checksum PASS;
- a business schema/data restore PASS;
- minden kritikus kontrollszám egyezik;
- `migration-schema.sql` restore PASS;
- `migration-history.sql` restore PASS;
- a migration history konzisztens.

Addig production továbbra is **NEM GO**.
