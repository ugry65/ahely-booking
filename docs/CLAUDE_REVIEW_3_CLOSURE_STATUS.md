# Claude review 3 – closure státusz

Dátum: 2026-08-26
Branch: `fix/claude-review-3-closure`
PR: #91

## Lezárt findingok

- P1-NEW-1: a jövőbeli pricing tervek megmaradása tudatos időbeli szemantika. Az admin Díjazás felület minden jövőbeli effektív változást időrendben megmutat és explicit figyelmeztet arra, hogy egy korábbi kezdőhónap módosítása nem törli a későbbi terveket.
- P1-NEW-2: a régi `admin_set_user_pricing_policy` authenticated EXECUTE joga visszavonva; kliensoldali pricing módosítás kizárólag az egységes `admin_set_user_pricing_configuration` műveleten keresztül történhet.
- Fix óradíj admin RPC/UI implementálva, auditált és regressziós tesztekkel lefedett.
- Fix/Free/Tréningterem pricing precedencia dokumentálva és regressziós teszttel lefedve.
- `CURRENT_FUNCTIONAL_BASELINE.md` v1.2 már nem jelöli a Fix admin RPC/UI-t kódoldali production gapként; a fennmaradó kapu manuális staging UAT.
- `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md` szinkronizálva az elkészült Fix admin funkcióval és a jövőbeli pricing-idővonal szabályával.
- Ismétlődő sorozatok `occurrence` / `following` / `series` rekord-szintű szemantikája külön kanonikus részletspecifikációban rögzítve: `docs/SERIES_SCOPE_SEMANTICS.md`.
- A scope-szemantikához regressziós teszt készült: `supabase/tests/database/100_series_scope_semantics.sql`.

## Teszt-hardening

A security hardening után elavult tesztek az új publikus API-szerződéshez igazítva. A scope regressziós tesztnek közvetlen booking/sorozat segédlekérdezésre van szüksége authenticated szerepkörben; ehhez a teszt saját `BEGIN ... ROLLBACK` tranzakciójában kap ideiglenes SELECT jogot. A rollback ezeket a GRANT-okat is visszavonja, ezért production jogosultság nem változik.

## Következő kapu

1. teljes CI zöld;
2. új, teljes adversarial Claude closure-review;
3. minden új finding javítása;
4. ismétlés addig, amíg a funkcionális/újraimplementálási dokumentáció 100%-os closure-t nem kap;
5. ettől külön production GO kapu marad a manuális UAT, backup/restore és monitoring bizonyítása.
