# User-szintű díjazási módok

Állapot: elfogadott üzleti döntés; frissítve 2026-08-26. Kapcsolódó issue: #82.

## Támogatott üzleti módok

1. `Sávos` (`tiered`) – **alapértelmezett**.
   - A havi összes elszámolandó normál óraszám alapján egyetlen sáv kerül kiválasztásra.
   - A kiválasztott sáv óradíja a teljes havi normál óraszámra vonatkozik.
   - Példa: 20 óra esetén 20 × 1 900 Ft = 38 000 Ft.
2. `Progresszív` (`progressive`).
   - A díjsávok egymás után csak a saját tartományuk óráira vonatkoznak.
   - Példa: 20 óra esetén 15 × 2 700 Ft + 5 × 1 900 Ft = 50 000 Ft.
3. `Fix óradíj` (`fixed_user`).
   - Admin userenként fix HUF/óra díjat állíthat be, időbeli érvényességgel.
   - A fix díj a normál, nem Tréningterem-csoportos órákra vonatkozik.
   - A jelenlegi DB-számító motor ezt a `user_price_overrides` rétegen keresztül már alkalmazza.
   - `tiered` vagy `progressive` policy mellett az érvényes fix override felülírja a normál órák sávos/progresszív számítását.
   - A végleges admin UI/RPC kezelés még implementációs gap; production előtt rendezendő, mert a szabály mostantól elfogadott üzleti funkció.
4. `Free` (`free`).
   - A user minden foglalása 0 Ft, beleértve a Tréningtermet és annak speciális díjazását is.
   - A `Free` minden más árazási réteget, így a fix user óradíjat is felülírja.
   - A foglalások és óraszámok ettől még megmaradnak riportálási célra.

## Precedencia

A számítási precedencia egyértelműen:

1. `Free` → teljes fizetendő 0 Ft;
2. egyébként, ha van az adott hónapra érvényes `user_price_overrides` fix díj → a normál órák ezen a fix díjon számolódnak;
3. ha nincs fix override → a user `tiered` vagy `progressive` policy-ja szerint számolódnak a normál órák;
4. Tréningterem csoportos foglalás külön speciális díjszabály szerint számolódik, kivéve `Free` usert.

## Mi számít elszámolandó foglalásnak

Csak az aktív, a foglalási rendszerben ténylegesen meglévő foglalás számlázódik. A törölt/lemondott foglalás nem növeli a havi óraszámot és nem kerül a fizetendő összegbe.

## Érvényesség és történet

- A díjazási mód és a fix díj userenként időben verziózott.
- A díjazási policy egy teljes havi elszámolási időszakra érvényes, ezért az érvényesség kezdete hónap első napja.
- Jövőbeli mód/díj előre rögzíthető.
- Azonos jövőbeli kezdőhónaphoz tartozó terv később módosítható; minden tényleges változás auditálandó.
- Explicit policy hiányában a rendszer `Sávos` módot alkalmaz.
- A történeti elszámolás későbbi díjmódosítástól nem változhat kontrollálatlanul.

## Adatmodell

A meglévő `pricing_tiers`, `user_price_overrides`, `special_room_rates`, `monthly_settlements`, `settlement_revisions` és `settlement_booking_lines` táblák megmaradnak.

A user alap díjazási policy-ját a `user_pricing_policies` tárolja. A fix óradíj külön, időben verziózott `user_price_overrides` réteg. Az újraimplementációban a konkrét táblastruktúra eltérhet, de ezt a két logikai réteget és a fenti precedenciát meg kell őrizni.

## Biztonság

- Közvetlen kliens/Data API írás díjazási policy-ra vagy fix óradíjra nem lehet megengedett.
- Módosítást kizárólag aktív admin számára elérhető, validált backend művelet végezhet.
- Minden változás auditált.
- A történeti elszámolási snapshot nem írható át kontrollálatlanul.

## Implementációs állapot

A központi havi díjszámító backend/DB logika elkészült és automatikus tesztekkel lefedett. Támogatja a sávos, progresszív, Free, fix user override és Tréningterem speciális számítást, valamint a törölt foglalások kizárását.

**Nyitott implementációs gap a production előtt:** a Fix óradíj üzleti funkcióhoz admin oldali, auditált beállítási RPC/UI szükséges, érvényességi hónappal. Ez már nem nyitott üzleti döntés, hanem implementációs feladat.
