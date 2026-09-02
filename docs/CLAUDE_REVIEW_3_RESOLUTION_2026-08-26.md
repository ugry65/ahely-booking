# A-Hely foglalási rendszer – Claude 3. review resolution

Dátum: 2026-08-26
Branch: `feature/82-pricing-modes`

## Összefoglalás

A 3. független Claude-review 91%-os újraimplementálhatóságot és két új P1 findingot jelzett a Fix óradíj production implementáció körül. Mindkettőt validáltuk a tényleges kód ellen és lezártuk. Az előző review-kból fennmaradt sorozat-scope dokumentációs rés is lezárult a `docs/RECURRING_SERIES_SCOPE_SEMANTICS.md` kanonikus kiegészítő specifikációval.

## P1-NEW-1 – jövőbeli Fix terv későbbi újraaktiválódása

**Státusz: CLOSED – dokumentált és látható idővonal-szemantika.**

A kód viselkedése összhangban áll az elfogadott időbeli pricing modellel: egy userhez több, különböző jövőbeli kezdőhónapra szóló díjazási változás előre ütemezhető. Egy korábbi kezdőhónap módosítása nem törli automatikusan a már későbbre rögzített tervet.

A hiány az volt, hogy az admin UI korábban csak a legközelebbi jövőbeli változást mutatta, ezért egy későbbi terv meglepetésként léphetett életbe.

Javítás:
- az admin Díjazás oldal minden usernél az összes jövőbeli effektív változást időrendben megmutatja;
- külön figyelmeztetés jelzi, hogy egy új, korábbi kezdőhónapú beállítás a későbbi, más kezdőhónapú terveket nem törli;
- a kiválasztott user előzménynézetében külön `Jövőbeli díjazási idővonal` jelenik meg;
- a szabály a `docs/PRICING_MODES.md` dokumentumban explicit rögzítve;
- `092_pricing_future_timeline.sql` regressziós teszt bizonyítja a jövőbeli terv megmaradását és az azonos kezdőhónapú Fix terv módosíthatóságát;
- ugyanebben a tesztben az override-intervallumok DB exclusion constraintje is ellenőrzött.

Nem vezettünk be automatikus cascade-delete-et, mert az korábban rögzített admin-szándék csendes törlését okozná és ellentétes lenne a több jövőbeli pricing változás támogatásával.

## P1-NEW-2 – legacy admin_set_user_pricing_policy közvetlen hívhatósága

**Státusz: CLOSED.**

A `202608250015_harden_pricing_configuration_api.sql` migráció visszavonja az `authenticated` szerepkör közvetlen EXECUTE jogát a legacy `admin_set_user_pricing_policy` RPC-ről.

A kliensoldali módosítás egyetlen támogatott útja az egységes `admin_set_user_pricing_configuration` wrapper, amely együtt kezeli a pricing policy és a Fix override idővonalát.

A `091_fixed_user_pricing_hardening.sql` teszt explicit ellenőrzi, hogy a legacy RPC már nem elérhető authenticated szerepkörből.

## Korábbi P1-1 – sorozat-scope szemantika

**Státusz: CLOSED dokumentációs szinten.**

A `docs/RECURRING_SERIES_SCOPE_SEMANTICS.md` technológiafüggetlenül rögzíti:
- `occurrence`: csak a kiválasztott alkalom;
- `following`: a kiválasztott + minden későbbi aktív jövőbeli alkalom;
- `series`: a teljes sorozat minden aktív jövőbeli alkalma, múltbeli és már cancelled bookingok visszaírása nélkül;
- több alkalmat érintő update/cancel atomi validációját;
- jogosultsági és 24 órás cutoff viselkedést;
- optimistic concurrency és idempotencia követelményét;
- az eredeti sorozat-generálási pillanatkép és az élő booking állapot különválasztását;
- a Tréningterem booking-specifikus csoportos díj öröklési/történeti viselkedését;
- a napi naptár és a szűkebb `Foglalásaim` kezelés közötti user-facing különbséget.

A dokumentum a `CURRENT_FUNCTIONAL_BASELINE.md` §11 kanonikus kiegészítő specifikációja.

## Automatikus teszt-gapek

A 3. review által jelzett fő hiányokból javítva:
- Fix + Tréningterem csoportos speciális díj: tesztelve, 5000 Ft/óra marad;
- Fixed → Progressive: tesztelve;
- Progressive → Fixed: tesztelve;
- Fixed → Tiered: tesztelve;
- múltbeli hónap Fix módosítása: tesztelve és tiltott;
- jövőbeli többváltozásos pricing idővonal: tesztelve;
- azonos kezdőhónapú Fix terv módosítása: tesztelve;
- legacy RPC publikus végrehajtási jogának tiltása: tesztelve;
- override exclusion constraint megléte: tesztelve.

Külön valódi kétfolyamatos concurrency shell-teszt a `user_price_overrides` konfigurációra még további hardeningként elkészíthető; az adatbázis GiST exclusion constraint + userenkénti advisory transaction lock kettős védelmet ad.

## UAT státusz

A Fix óradíj admin RPC/UI elkészült, ezért:
- `UAT-PRICING-05`: `NEM FUTOTT`, már tesztelhető;
- `UAT-PRICING-06`: `NEM FUTOTT`, már tesztelhető.

A production infrastruktúra UAT-k továbbra is blokkoltak addig, amíg backup/restore és monitoring implementáció nincs kész.

## Fennmaradó production teendők

A kód- és dokumentációs P1 findingok lezárása után a fő production kapuk:
1. legfrissebb Application és Database CI teljes zöld állapota;
2. teljes manuális staging UAT, beleértve a Fix óradíj idővonalat és sorozat-scope műveleteket;
3. production backup/off-site mentés;
4. sikeres restore-drill;
5. production monitoring/heartbeat + alert drill;
6. végső független review;
7. explicit production GO.
