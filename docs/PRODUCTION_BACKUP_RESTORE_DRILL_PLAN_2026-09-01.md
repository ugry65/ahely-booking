# A-Hely – Production backup restore drill terv

Dátum: 2026-09-01
Státusz: előkészítve, tényleges restore drill még nem futott le.

## Cél

Bizonyítani, hogy a production adatbázisról készült, client-side `age` titkosítású mentés ténylegesen visszaállítható úgy, hogy production és staging adat ne kerüljön veszélybe.

## Biztonsági alapelv

A restore drill kizárólag izolált PostgreSQL 17 környezetben történhet. Production vagy staging adatbázisra a drill nem futtatható.

A recovery private key nem kerül GitHubba, Google Drive-ra vagy Backblaze B2-re. A visszafejtés azon a helyi gépen történik, ahol a recovery key biztonságosan rendelkezésre áll.

## Forrásbackup

Első bizonyított dual-target production backup:

- GitHub Actions run: `33547980831`
- artifact: `ahely-booking-production_20260901T191321Z_387e40d5afcc.tar.gz.age`
- Supabase/PostgreSQL dump image: `ghcr.io/supabase/postgres:17.6.1.165`
- Google Drive feltöltés és read-back SHA-256 ellenőrzés: PASS
- Backblaze B2 feltöltés és read-back SHA-256 ellenőrzés: PASS

A backup bundle tartalma:

- `roles.sql`
- `schema.sql`
- `data.sql`
- `migration-history.sql`
- `control-counts.json`
- `manifest.json`
- `DATA_SHA256SUMS`
- `SHA256SUMS`

## Drill lépései

1. A titkosított artifact letöltése az egyik off-site célról a helyi gépre.
2. A `.sha256` sidecar letöltése és a titkosított artifact SHA-256 ellenőrzése.
3. Az artifact visszafejtése a helyi recovery private key-jel.
4. A tar.gz kicsomagolása ideiglenes, helyi könyvtárba.
5. A belső `SHA256SUMS` ellenőrzése.
6. Izolált PostgreSQL 17 tesztpéldány indítása.
7. Restore a dokumentált sorrendben, production/staging kapcsolat nélkül.
8. Restore utáni technikai ellenőrzések.
9. Restore utáni üzleti/adatkonzisztencia ellenőrzések.
10. A tesztpéldány és a visszafejtett ideiglenes fájlok kontrollált eltávolítása.

## Kötelező restore utáni ellenőrzések

A drill csak akkor PASS, ha legalább az alábbiak igazoltak:

- a bundle és minden belső komponens checksumja helyes;
- a séma visszaállt;
- a kritikus táblák lekérdezhetők;
- `auth.users` darabszám egyezik a backup `control-counts.json` értékével;
- `public.profiles` darabszám egyezik;
- `public.rooms` darabszám egyezik;
- `public.user_room_permissions` darabszám egyezik;
- `public.booking_series` darabszám egyezik;
- összes, aktív és lemondott foglalások darabszáma egyezik;
- `public.booking_cancellations` darabszám egyezik;
- `public.audit_logs` darabszám egyezik;
- `public.monthly_settlements` darabszám egyezik;
- `public.settlement_revisions` darabszám egyezik;
- `public.settlement_booking_lines` darabszám egyezik;
- a migration history visszaállt és konzisztens;
- a foglalási, jogosultsági, audit- és elszámolási adatok között nem látható integritási hiba.

## Fail-closed feltételek

A drill azonnal FAIL, ha:

- a titkosított artifact vagy a sidecar checksum nem egyezik;
- a visszafejtés sikertelen;
- bármely belső checksum hibás;
- a restore cél nem bizonyítottan izolált PostgreSQL 17 tesztpéldány;
- a restore bármely kötelező komponense hibázik;
- a kontroll darabszámok közül bármelyik eltér;
- a restore után kritikus adat- vagy referenciális konzisztenciahiba látható.

## Következő kézi előfeltétel

A helyi restore drillhez ellenőrizni kell, hogy a Windows gépen elérhető-e Docker. Első ellenőrző parancs PowerShellben:

```powershell
docker --version
```

Ha Docker nem érhető el, külön döntünk a legkisebb kockázatú izolált PostgreSQL 17 környezetről. Production vagy staging adatbázist kerülőútként sem használunk.
