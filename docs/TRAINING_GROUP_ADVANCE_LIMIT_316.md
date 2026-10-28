# Tréningterem – csoportos előrefoglalás (#316)

Döntés: 2026-10-28. Megerősítve a független PR #317 review után.

- Normál felhasználó, Tréningterem, egyéni használat: legfeljebb 10 nap előre, a meglévő alacsonyabb felhasználói limit figyelembevételével.
- Normál felhasználó, Tréningterem, csoportos használat: **fix 180 nap előre**.
- A csoportos 180 napos szabály **szándékosan független** a `default_advance_booking_days`, `training_room_advance_days` és a felhasználói `advance_booking_days_override` értékétől. Ez a felhasználó által megerősített üzleti döntés, nem implementációs hiányosság.
- Nem vezetünk be felhasználónként állítható külön Tréningterem-limitet.
- Az admin, a többi terem, a jogosultságok, az ismétlődés és az átfedésvédelem szabályai változatlanok.

## Megvalósítás és ellenőrzés

- A szerveroldali `public.assert_booking_request` a használattípus alapján érvényesíti a korlátot; a közös validátor a létrehozási és módosítási útvonalakat is védi.
- A Tréningterem naptárában külön egyéni és csoportos foglalási indítás érhető el, a megfelelő használattípus előtöltésével.
- A 10/11 és 180/181 napos létrehozási határtesztek, valamint a naptár handoff tesztjei bekerültek.
- További pgTAP regressziós tesztek: a 3 napos általános felhasználói override nem korlátozza a csoportos 180 napot, de az egyéni foglalást igen; jogosulatlan csoportos foglalás tiltása; csoportos foglalás 180/181 napos módosítási határa; normál user csoportos sorozatkészítésének tiltása és admin sorozatkészítés engedélyezése.
- A PR #317 `c1d8a4a` commitjának négy GitHub CI folyamata sikeres (Application checks, Database tests, Release evidence, Staging schema reference inventory). A legfrissebb `5d1c535` commit mind a négy GitHub CI folyamata sikeres, beleértve a 48 sorozattesztet és a foglalásmódosítási regressziós teszteket.
- A független review M-1 megállapítását a fenti, megerősített üzleti döntés feloldja. A célzott módosítási, jogosultsági és ismétlődési regressziós tesztek elkészültek; a projekt FS-ellenőrzés, a bejelentkezett felhasználói staging UAT és a végső független review még hátravan. A Vercel preview deployment `dpl_AcFcDxzV28v51rS3u2NuTQ9uhBJo` READY (`5d1c535`), de ez önmagában nem bizonyítja, hogy a staging Supabase adatbázison az új migráció alkalmazva van.
- A PR nem merge-elhető és production nem telepíthető a hátralévő ellenőrzések nélkül.

## 2026-10-28 – Független review és staging migrációs bizonyíték

- Claude független kódreview: **kód APPROVE**, production **NO-GO** a staging history-eltérés rendezéséig. Kritikus/magas/közepes kódhiba nincs; két nem blokkoló LOW megállapítás.
- Projektgazda: 10 napon túli csoportos foglalás stagingen sikeres; production GO kifejezetten megadva.
- Staging Supabase projekt: `fvwapntzhavhgazeflri`; a tényleges alkalmazott history rekord `20261028160455_training_group_180_day_limit`, a GitHub-fájl `20261028151000_training_group_180_day_limit.sql`.
- **Read-only, teljes SQL bájtegyezés bizonyítva**: `array_to_string(statements, '') = <GitHub fájl tartalma>` → `true`; mindkét MD5 `64f0ec029553a519611d1d3d3fc4e74b`. A staging tényleges függvényében a 180 napos és az egyéni limitág jelen van.
- Production Supabase `yasrmxwjojepessivhmc`: sem a `20261028151000`, sem a `20261028160455` migráció nincs jelen (read-only lista).
- **Nyitott release-gate:** staging migration ledger kontrollált `reverted`/`applied` rendezése, majd újraellenőrzés; release-evidence frissítése és production migrációs/deployment előfeltételek. A korábbi staging history-ban más, történeti eltérések is vannak; tilos a teljes ledger vak javítása vagy `db push` előzetes leltár nélkül.
- A staging migráció azonosítóeltérése abból keletkezett, hogy a PR SQL-t közvetlenül a Supabase `apply_migration` eszközzel alkalmaztuk, amely új időbélyeg-verziót adott. Jövőben a repository migrációazonosítóját megőrző, ellenőrzött kiadási folyamatot kell használni.
- A jelen bejegyzés nem igazol production deploymentet, és nem helyettesíti a release-gate-eket.
