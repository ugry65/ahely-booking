# Issue #82 – user díjazási módok, havi díjszámítás és settlement snapshot

## Elfogadott üzleti szabályok

- Csak az aktív, a foglalási rendszerben ténylegesen meglévő foglalások számlázódnak.
- Törölt / lemondott foglalás nem növeli a havi óraszámot és nem számlázódik.
- Userenként három díjazási mód állítható:
  - `tiered` – Sávos, nem progresszív; ez a default.
  - `progressive` – Progresszív sávos.
  - `free` – teljes user-szintű 0 Ft, a Tréningteremre is.
- Díjazási mód csak teljes hónapra érvényes, hónap első napjától.
- Jövőbeli mód előre beállítható.
- Korábbi hónap díjazási módja nem dátumozható vissza.
- A már lezárt havi elszámolás későbbi ár-, foglalás- vagy díjazási mód változástól nem változhat.

## Aktuális sávok

- 1–15 óra: 2 700 Ft/óra.
- 15 óra felett–60 óráig: 1 900 Ft/óra.
- 60 óra felett: 1 700 Ft/óra.

Nem progresszív Sávos esetben a teljes havi normál óraszám a kiválasztott sáv óradíját kapja. Példa: 20 óra → 20 × 1 900 = 38 000 Ft.

Progresszív esetben a sávok egymás után számolódnak. Példa: 20 óra → 15 × 2 700 + 5 × 1 900 = 50 000 Ft.

## Technikai megoldás

### User policy

A `user_pricing_policies` időben verziózott táblában tároljuk a user díjazási módját. Az admin RPC biztosítja az érvényességi dátum, jogosultság és audit szabályokat.

### Központi havi kalkulátor

A `calculate_monthly_pricing(user, month)` az egyetlen központi pénzügyi számítás. A UI nem implementál külön díjszámítási szabályt.

A motor kezeli:

- Sávos;
- Progresszív;
- Free;
- meglévő egyedi fix user-óradíj;
- Tréningterem csoportos speciális díj;
- törölt foglalások kizárása.

A kalkulátor belső építőelem; normál kliens közvetlenül nem hívhatja. Admin és engedélyezett saját dashboard külön jogosultság-ellenőrzött wrapperen keresztül használja.

### Havi lezárás és immutable snapshot

Csak már befejeződött hónap zárható le. A lezárás user + hónap szinten, tranzakcióban történik és advisory lock védi a párhuzamos dupla lezárástól.

A lezáráskor:

1. lefut a központi havi kalkulátor;
2. létrejön a `settlement_revisions` snapshot;
3. eltárolódik a díjazási mód, a teljes pricing breakdown és a calculation input hash;
4. minden aktív foglalás bekerül a `settlement_booking_lines` snapshotba;
5. progresszív díjazásnál egy foglalás több sorrészre bomolhat, ha sávhatárt lép át;
6. a snapshot sorok összegének és időtartamának egyeznie kell a központi kalkulátorral, különben a tranzakció meghiúsul;
7. a lezárt revision és booking snapshot sorok utólag nem módosíthatók;
8. a lezárás auditnaplóba kerül.

A `Havi órák és fizetendő` admin képernyő nyitott hónapnál élő kalkulációt, lezárt hónapnál viszont a történeti settlement snapshotot jeleníti meg.

## Kötelező regressziós tesztek

A branch automatikus DB tesztjei lefedik többek között:

- 15 / 20 / 60 / 61 órás sávhatárok;
- 20 órás Sávos = 38 000 Ft;
- 20 órás Progresszív = 50 000 Ft;
- Free normál helyiség és Tréningterem = 0 Ft;
- törölt foglalás kizárása;
- egyedi fix user-díj;
- Tréningterem speciális díj;
- normál user pénzügyi admin jogosultságának tiltása;
- aktuális hónap idő előtti lezárásának tiltása;
- progresszív sávhatárt átlépő foglalás több snapshot-sorra bontása;
- snapshot összeg- és időtartam-konzisztencia;
- dupla lezárás tiltása;
- snapshot immutabilitás;
- auditnapló.

## Deployment elv

A fejlesztés külön branchen és PR-ben történik. Először CI, majd staging DB + preview UAT. Production DB és `main` csak külön ellenőrzés és explicit jóváhagyás után módosítható.
