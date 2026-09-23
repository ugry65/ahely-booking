# GitHub #178 – Admin díjszabás és foglalásszintű óradíj

## Források és döntési sorrend

Ez a terv az aktuális Funkcionális Specifikáció, az
`A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`, a #178 jóváhagyott
követelményei és a `main` branch tényleges adatmodellje alapján készült.

Nem jön létre párhuzamos árazási rendszer. A megoldás a meglévő
`pricing_tiers`, `user_price_overrides`, `special_room_rates`,
`monthly_settlements`, `settlement_revisions` és
`settlement_booking_lines` táblákat használja.

Az alkalmazott óradíj sorrendje:

1. foglalásszintű admin óradíj;
2. user időben verziózott egyedi óradíja;
3. Tréningterem csoportos használatának időben verziózott alapdíja;
4. a normál havi összperchez tartozó, időben verziózott központi sáv.

A Tréningterem 5 000 Ft-os külön díja a korábban elfogadott szabály szerint
csak a **csoportos** használatra vonatkozik. Az egyéni használat normál
díjazású.

## Adatmodell

- A `bookings.hourly_rate_override_huf` kizárólag az adott foglalás admin
  felülírását tárolja. `NULL` esetén automatikus árazás történik.
- A felülírás beállítóját, idejét és indokát külön oszlopok őrzik; minden
  változás az append-only `audit_logs` táblába is bekerül teljes előtte/utána
  állapottal.
- A központi, user- és Tréningterem-díjak továbbra is `valid_from` / `valid_to`
  időszakokkal verziózottak. Módosításkor a korábbi időszak lezárul, nem íródik
  át.
- Az elszámolás sorai az alkalmazott forrást, szabályazonosítót, óradíjat,
  időtartamot és összeget snapshotként tárolják.
- Minden settlement revision és booking line immutable történeti snapshot. Új,
  indokolt revision készíthető, de korábbi revision nem írható át és nem
  törölhető; ez megőrzi az utólagos korrekció elfogadott lehetőségét.

## Sávos számítás

A normál havi sáv nem progresszív: a havi normál foglalási összperc egyetlen
sávot választ, és az automatikus központi díjas foglalások erre az óradíjra
számolódnak. A foglalás- vagy user-szintű felülírással árazott normál
foglalások percei is beleszámítanak a havi sáv meghatározásába, de saját
óradíjukon számolódnak. A Tréningterem csoportos percei nem növelik a normál
sávos összpercet.

Az óradíj és az időtartam külön adat. A tétel összege:

`round(duration_minutes × hourly_rate_huf / 60)`.

## Történeti reprodukálhatóság

- Egy díjszabási változás új érvényességi időszakot nyit, ezért a korábbi
  szolgáltatási dátumokra vonatkozó szabály nem változik.
- A foglalásszintű felülírás a booking része, ezért a későbbi központi vagy
  user tarifa nem írja felül.
- A havi elszámolás minden végleges számítása külön immutable revisiont és
  booking line-okat őriz. Utólagos korrekció új, auditált revisiont készít, a
  korábbi állapot így későbbi booking- vagy tarifaállapot mellett is
  reprodukálható marad.

## Jogosultság és tranzakció

- Díjat csak aktív admin módosíthat SECURITY DEFINER RPC-n keresztül.
- A táblák deny-by-default RLS-e megmarad; közvetlen kliensírás nincs.
- Az admin booking létrehozása/szerkesztése és a foglalásszintű díj mentése
  egyetlen adatbázis-tranzakcióban történik.
- Normál user booking RPC-jei nem kapnak árparamétert.
- Az AllBooked import nem ad át árparamétert; az új booking mező defaultja
  `NULL`, ezért import nem hozhat létre véletlen felülírást.

## Bevezetési sorrend

1. migráció és pgTAP regressziós tesztek;
2. admin Díjszabás oldal és user Díjazás rész;
3. admin booking ár-előnézet és foglalásszintű felülírás;
4. teljes unit/typecheck/build és lokális DB-tesztek;
5. független security/data-integrity review;
6. PR és CI;
7. staging DB-migráció, staging UAT;
8. production csak külön projektgazdai jóváhagyással.
