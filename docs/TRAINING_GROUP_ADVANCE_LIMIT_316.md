# Tréningterem – csoportos előrefoglalás (#316)

Döntés: 2026-10-28.

- Normál felhasználó, Tréningterem, egyéni használat: legfeljebb 10 nap előre.
- Normál felhasználó, Tréningterem, csoportos használat: legfeljebb 180 nap előre.
- A 180 napos külön szabály nem szorítható az általános 90 napos előrefoglalási limit alá.
- Az admin, a többi terem, a jogosultságok, az ismétlődés és az átfedésvédelem szabályai változatlanok.

A 2026-10-28-án ellenőrzött staging DB-ben a public.assert_booking_request függvény a Tréningterem mindkét használattípusára a kisebbik általános és training_room_advance_days limitet használta. A beállítások: default_advance_booking_days=90, training_room_advance_days=10.

## Következő ellenőrzések

1. A teljes aktuális FS-sel és main migrációkkal egyeztetni.
2. A szerveroldali validációt módosítani, egyéni 10 és csoportos 180 napra; a csoportos szabály ne essen vissza 90 napra.
3. A foglalási felület és dátumválasztó ugyanezt engedje.
4. 10/11 és 180/181 napos határok, létrehozás/módosítás, jogosultságok és ütközés tesztelése.
5. Független review, staging UAT, külön production GO.

Státusz: csak dokumentáció; a működés még nem változott.
