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
- A PR #317 `3312af3` commitjának négy GitHub CI folyamata sikeres (Application checks, Database tests, Release evidence, Staging schema reference inventory).
- A független review M-1 megállapítását a fenti, megerősített üzleti döntés feloldja. A hiányzó célzott módosítási, jogosultsági és ismétlődési regressziós teszteket továbbra is pótolni kell, illetve ellenőrizni kell a projekt FS-t és a staging működést.
- A PR nem merge-elhető és production nem telepíthető a hátralévő ellenőrzések nélkül.
