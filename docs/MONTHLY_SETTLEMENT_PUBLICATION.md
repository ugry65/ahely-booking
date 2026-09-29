# Havi elszámolás lezárása és publikálása

Állapot: `feature/monthly-settlement-publication` fejlesztési ág. A staging adatbázisra történő telepítés és az UAT még hátravan.

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
- Alkalmazás tesztek: `pnpm test`; statikus ellenőrzés: `pnpm typecheck`; production build: `pnpm build`.

## Forrásdokumentumok státusza

A repositoryban megtalálható funkcionális specifikáció fájlja v1.0, a projektkontextus pedig korábbi, kötelező havi lezárást nem előíró üzleti állapotot is tartalmaz. Az „AI újraimplementálási specifikáció” aktuális példánya a vizsgált repository-ágban nem található. Ezért a lezárási és publikálási szabály forrása a 2026-09-29-i fejlesztési követelmény és az abban elfogadott cutoff-alapú lezárhatóság; a hiányzó specifikáció nem helyettesíthető kitalált tartalommal.
