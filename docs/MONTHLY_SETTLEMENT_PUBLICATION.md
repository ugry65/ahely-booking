# Havi elszámolás lezárása és publikálása

Állapot: `feature/monthly-settlement-publication` fejlesztési ág, PR #257. A staging migration megtörtént, a projektgazda a staging UAT-ot sikeresen elvégezte és üzletileg elfogadta. A PR #258 staging séma reconciliationje független Claude-review szerint merge blocker nélkül rendben van. A PR #257 független Claude-review-ja a pénzügyi, cutoff, korrekciós és jogosultsági működést megfelelőnek találta; egy merge blockert jelölt: hiányzott a valódi, két DB-kapcsolatos advisory-lock konkurenciateszt. Az új regressziós teszt eredményét a jelen PR CI-futása igazolja, amikor elkészül. A PR #257-et az új független follow-up review előtt nem merge-eljük; production továbbra sem módosult.

## Meglévő modell

A díjakat a `calculate_monthly_pricing` számolja. Az admin összesítő a legfrissebb havi revisiont vagy — revision hiányában — élő előnézetet mutatja. A `monthly_settlements` egy user/hónap fejlécrekordot tárol; a `settlement_revisions` és `settlement_booking_lines` megőrzött pénzügyi snapshotot ad. Az admin történeti díjkorrekciója már indokolt, auditált új revisiont készít.

Ez a fejlesztés a meglévő pénzügyi táblákat használja. Az új `monthly_settlement_periods` rekord kizárólag az egész hónap atomikus publikálási eseményét és ellenőrző összesítését rögzíti.

## Lezárhatósági szabály

Az admin a budapesti naptár szerinti aktuális hónapot a hónap utolsó napján is lezárhatja, ha nincs olyan aktív, az adott hónapba eső foglalás, amelyet normál user a meglévő módosítási/lemondási határidő alapján még megváltoztathat. A rendszer ezt így ellenőrzi:

- a `cancellation_cutoff_hours` aktuális beállítását használja;
- blokkoló minden érintett foglalás, amelynek kezdete `most + cutoff` időponttal egyenlő vagy későbbi;
- a pontos határidő-pillanat blokkoló, mert a jelenlegi foglalási RPC a határidőnél még elfogadja a normál user módosítását;
- hiányzó/hibás cutoff-beállítás esetén a lezárás hibával megáll;
- a `Europe/Budapest` időzóna határozza meg a hónapba tartozást és a jelenlegi hónapot.

A hónapzárás és a foglalási írás ugyanazt a tranzakciós advisory lockot használja. Sikeres publikálás után normál user a hónap elszámolását befolyásoló foglalási változtatást már nem hajthat végre.

## Folyamat és korrekció

1. Az admin a `/admin/havi-orak` oldalon hónaponként megnyitja a szerveroldali előnézetet.
2. Az előnézet mutatja a felhasználók számát, az összes elszámolt percet/órát, a fizetendő összeget és az esetleges cutoff-blokkolókat.
3. A „Hónap lezárása” után külön megerősítés kell. A lezárási RPC tranzakcióban előállítja a user/hónap revisioneket, lezárja az érintett fejléceket, létrehozza az immutable hónaprekordot és audit-eseményt ír.
4. A `Foglalásaim` csak az aktuális user saját legutóbbi publikált revisionjét kérheti le. A lekérő RPC nem fogad user-azonosítót. Ha nincs lezárt hónap, nem jelenik meg pénzügyi kártya.
5. Korrekció új revisiont hoz létre, annak indoka kötelező, az aktív revision-pointer előrelép, a korábbi revision és a lezáráskori összesítő megmarad.
6. Admin lezárás után is lemondhat foglalást: a cancellation auditindoka kötelező, és ugyanabban a tranzakcióban új havi revision készül. Egyéb, lezárt hónapot érintő admin foglalásmódosítás csak kifejezett auditált korrekciós műveleten keresztül engedett.

Az első verzió nem mutat becslést, befizetést, tartozást, fizetési státuszt/módot, célhelyet vagy számlázási információt.

## Biztonság és ellenőrzés

- Nincs kliens-hozzáférés a `monthly_settlements`, `settlement_revisions`, `settlement_booking_lines` pénzügyi táblákhoz.
- Admin műveletek aktív admin jogosultságú RPC-k; a hónaplezárás ismétlése hibával áll meg, részleges állapot nem marad.
- User olvasás: `list_my_latest_closed_monthly_settlement()` → `auth.uid()` → saját `closed_revision_id` → publikált hónap. Nincs paraméterezhető másik user.
- Automatizált pgTAP tesztek: `supabase/tests/database/117_monthly_settlement_publication.sql`.
- A `scripts/test-monthly-settlement-close-concurrency.sh` két külön `psql` kapcsolattal, `pg_stat_activity` és `pg_blocking_pids` alapján igazolt advisory-lock várakozással teszteli a két admin egyidejű zárását, a zárás alatti publikus booking INSERT-et és a lemondási írás guardját. FIFO-val tartja a záró tranzakció commitját; a várakozás felismerése után engedi el. A publikus `cancel_booking` régi alkalomnál már a 24 órás cutoff miatt elutasít, ezért az UPDATE guard párhuzamos útját normál user JWT-vel, célzottan emelt SQL-szerepkörrel ellenőrzi. A teszt kizárólag helyi DB URL-en futhat, timeout védi, és a DB runner és a Database tests CI is hívja.
- A sorozatos foglalási RPC lezárt hónap utáni elutasítását és a budapesti tavaszi DST hónapforduló pénzügyi besorolását a `117` és `118` pgTAP fájl vizsgálja. A hónap utolsó napját a `117` helper-szintű, rögzített időpontú ellenőrzése bizonyítja; production időmockolás nem került be.
- Alkalmazás tesztek: `pnpm test`; statikus ellenőrzés: `pnpm typecheck`; production build: `pnpm build`.

## Forrásdokumentumok státusza

A jóváhagyott FS v1.0 és az `A-Hely_Foglalasi_Rendszer_AI_Ujraimplementalasi_Specifikacio_2026-09-04.md` elérhető ChatGPT projektfájlként; az AI-specifikáció nincs verziózva a repositoryban. Ellenőriztük az AI-specifikáció foglalási módosítás/24 órás lemondás, időbeli díjszabás, immutable revision, audit és fail-closed előírásait. A későbbi, 2026-09-29-i explicit feature-követelmény szűkíti a régi FS aktuális becslésre, befizetésre és kötelező havi lezárás hiányára vonatkozó részeit. A lezárás szabadon választható admin művelet, de a usernek kizárólag publikált revision jelenhet meg.

A `20260829145720_allow_past_booking_creation.sql` alapján normál user is létrehozhat múltbeli bookingot. Emiatt a 24 órás módosítási/lemondási határidő lejárta önmagában nem védené a lezárt snapshotot: publikálás után normál user nem hozhat létre, módosíthat vagy mondhat le az adott hónap elszámolását érintő bookingot. A backend trigger ezt a lezárt hónap alapján kényszeríti ki; admin korrekció új auditált revisiont hoz létre. Pontosan a cutoff pillanatában a meglévő `clock_timestamp() > start_at - cutoff` guard szerint a lemondás még megengedett, ezért a zárást ez a booking még blokkolja.

Az [eredeti 2026-09-29-i migration history audit](STAGING_MIGRATION_HISTORY_AUDIT_2026-09-29.md) történeti pillanatképet rögzít; a későbbi staging reconciliation és feature migration már megtörtént. A mostani tesztváltozásokhoz új DB schema migration nem szükséges.
