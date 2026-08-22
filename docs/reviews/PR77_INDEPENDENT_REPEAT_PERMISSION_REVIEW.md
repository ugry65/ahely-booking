# PR #77 – független ismétlődési jogosultsági review brief

## Szerep

Független senior/security reviewer. A cél nem az implementáció megerősítése, hanem a jogosultsági, migrációs, concurrency és regressziós hibák aktív keresése.

## Elfogadott üzleti szabály

A kanonikus ismétlődő foglalási jogosultság **user-szintű**.

Normál user:
- repeat KI → sehol nem hozhat létre sorozatot;
- repeat BE → minden olyan normál helyiségben ismételhet, amelyre effektív `can_book` joga van;
- `can_book` származhat aktív helyiségcsoportból vagy közvetlen user–szoba kivételből;
- Tréningteremben normál user repeat BE mellett sem hozhat létre sorozatot.

Admin:
- a normál repeat korlátozás nem vonatkozik rá;
- Tréningteremben is ismételhet;
- a normál user 90 napos, illetve Tréningterem 10 napos előrefoglalási limitje nem vonatkozik rá.

Előrefoglalási defaultok:
- normál helyiség: 90 nap;
- Tréningterem normál user: 10 nap;
- ezek külön #44-ben adminból konfigurálható rendszerbeállításként kezelendők;
- a jelen PR azt bizonyítja, hogy a sorozat minden alkalma a központi validatoron megy át és az admin bypass szerveroldali.

## Kanonikus adatmodell

`profiles.can_repeat_bookings boolean`

Normál user effektív repeat joga egy helyiségre:

`profiles.can_repeat_bookings = true`
AND
`effective can_book = true`
AND
`room.is_training_room = false`

A történeti `user_room_permissions.can_repeat` mező kompatibilitási adat, **nem lehet önálló effektív repeat-jog forrása**.

## Migrációs/adatmegőrzési szabály

Meglévő user nem veszíthet repeat jogosultságot.

Ezért:
- migrációkor bármely legacy direct `can_repeat=true` → `profiles.can_repeat_bookings=true`;
- régi kompatibilis RPC-n érkező `can_repeat=true` user-szintű repeat jogot kapcsol be;
- a legacy flag nem szűkítheti az effektív repeat jogot egyetlen szobára;
- explicit user-szintű repeat KI törli a user legacy `can_repeat=true` jelzőit;
- a meglévő `can_book`, csoporttagság és egyéb jogosultságok nem változhatnak.

## Kiemelten vizsgálandó fájlok

- `supabase/migrations/202608220016_user_level_repeat_permission.sql`
- `supabase/tests/database/009_recurring_booking_rpc.sql`
- `supabase/tests/database/012_recurring_booking_ui_support.sql`
- `supabase/tests/database/029_user_level_repeat_permission.sql`
- `supabase/tests/database/030_recurring_advance_limits.sql`
- `scripts/test-repeat-permission-concurrency.sh`
- `.github/workflows/database-tests.yml`
- `src/app/(protected)/admin/felhasznalok/actions.ts`
- `src/app/(protected)/admin/felhasznalok/page.tsx`
- `src/app/(protected)/admin/hozzaferesek/page.tsx`
- `docs/RECURRING_PERMISSION_RULES.md`

## Kötelező review kérdések

### A. Jogosultsági modell
- Valóban user-szintű-e az effektív repeat jog minden normál szobában?
- Van-e bármilyen út, ahol egy legacy room-szintű `can_repeat` önmagában effektív jogot ad?
- Csoportból és direct grantból származó `can_book` egyformán működik-e?
- Tréningterem normál usernek minden backend úton tiltott-e?
- Admin bypass minden szükséges szerveroldali úton érvényes-e?

### B. Legacy kompatibilitás
- A backfill biztosítja-e, hogy korábbi `can_repeat=true` user ne veszítsen jogot?
- Régi `admin_set_user_room_permission(..., can_repeat=true, ...)` hívás biztonságosan promotálja-e a user-szintű jogot?
- A régi mező megtartása okozhat-e két egymással versengő truth source-ot?
- Explicit user-szintű KI után maradhat-e stale TRUE flag, amely később váratlanul visszakapcsolja a jogot?

### C. Concurrency
Különösen vizsgáld:
- `admin_set_profile_repeat_permission(... false ...)` és legacy `admin_set_user_room_permission(... true ...)` egyidejű futását;
- a két RPC ugyanazt a profile-level advisory lockot azonos lock orderben használja-e;
- lehetséges-e deadlock (profile row ↔ user_room_permissions row fordított lock order miatt);
- a `scripts/test-repeat-permission-concurrency.sh` valódi külön PostgreSQL-kapcsolatokkal bizonyít-e mindkét sorrendet;
- a végállapot a commit-sorrenddel konzisztens-e.

### D. Security / RPC
- minden új SECURITY DEFINER függvénynél `search_path=''` megfelelő-e;
- `public`/`anon` EXECUTE revoke teljes-e;
- normál authenticated user közvetlen RPC-val módosíthat-e repeat jogot;
- audit before/after + correlation ID megfelelő-e;
- nincs-e jogosultság-emelési vagy service-role oldalhatás.

### E. Előrefoglalási limit
- `create_booking_series` minden nem-kizárt alkalomnál meghívja-e a központi `assert_booking_request` validátort;
- emiatt normál user későbbi, 90 napon túli alkalma megfelelően elutasított-e;
- admin valóban bypassolja-e a 90/10 napos limitet;
- a tesztek ezt ténylegesen bizonyítják-e, nem csak a függvényforrást vizsgálják.

### F. UI regresszió
- a room-szintű repeat checkbox valóban eltűnt-e a kompatibilitási jogosultsági oldalról;
- a user-szintű repeat kapcsoló a Felhasználók szerkesztőben egyértelmű-e;
- a booking calendar / mobil UX regresszióvédett részeihez a PR nem nyúl-e szükségtelenül.

## Kimenet

1. Executive summary: `APPROVE` / `APPROVE WITH FIXES` / `REQUEST CHANGES`.
2. Findingok: CRITICAL / HIGH / MEDIUM / LOW.
3. Minden findinghoz fájl/funkció, kockázat, reprodukció vagy érvelés, konkrét javítás, regressziós teszt.
4. Külön authorization + migration + concurrency assessment.
5. `NOT VERIFIED` jelölés minden nem bizonyítható pontra.
6. Végső merge recommendation.

CRITICAL/HIGH finding esetén UAT/merge nem folytatható javítás és új teljes regressziós futás nélkül.
