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

A motor kezeli a Sávos, Progresszív és Free módot, a meglévő egyedi fix user-óradíjat, a Tréningterem csoportos speciális díját és a törölt foglalások kizárását.

A kalkulátor belső építőelem; normál kliens közvetlenül nem hívhatja. Admin és engedélyezett saját dashboard külön jogosultság-ellenőrzött wrapperen keresztül használja.

### Havi lezárás és immutable snapshot

Csak már befejeződött hónap zárható le. A lezárás user + hónap szinten, tranzakcióban történik és advisory lock védi a párhuzamos dupla lezárástól.

A lezáráskor lefut a központi havi kalkulátor, létrejön a `settlement_revisions` snapshot, eltárolódik a díjazási mód, a teljes pricing breakdown és a calculation input hash, majd minden aktív foglalás bekerül a `settlement_booking_lines` snapshotba. Progresszív díjazásnál egy foglalás több sorrészre bomolhat, ha sávhatárt lép át.

A snapshot sorok összegének és időtartamának egyeznie kell a központi kalkulátorral, különben a tranzakció meghiúsul. A lezárt revision és booking snapshot sorok utólag nem módosíthatók. A lezárás auditnaplóba kerül.

A `Havi órák és fizetendő` admin képernyő nyitott hónapnál élő kalkulációt, lezárt hónapnál a történeti settlement snapshotot jeleníti meg. A lezárt sor akkor is megmarad a pénzügyi nézetben, ha a későbbi élő foglalási állapot már eltér tőle.

### Admin lezárási művelet

A `Havi órák és fizetendő` oldalon a már befejeződött, még nyitott user/hónap sor lezárható. Aktuális vagy jövőbeli hónap nem zárható le. A lezárt sor revision számmal és lezárási időponttal jelenik meg, és újabb lezárás nem indítható rá.

## Kötelező regressziós tesztek

A branch automatikus DB tesztjei lefedik többek között a 15 / 20 / 60 / 61 órás sávhatárokat, a Sávos és Progresszív referenciaösszegeket, Free és Tréningterem esetet, törölt foglalást, egyedi fix díjat, pénzügyi jogosultságokat, idő előtti lezárás tiltását, progresszív foglalás-splitet, snapshot-konzisztenciát, dupla lezárás tiltását, immutabilitást és auditnaplót.

## Jelenlegi PR határa

A #90 PR tartalmazza a user díjazási módokat, a központi havi számítást, az admin havi fizetendő nézetet, valamint a havi settlement lezárást és immutable snapshotot. A #82 issue továbbra is nyitva marad a befizetések/részfizetések, korrekciók és végleges export/számlázási folyamat teljes elkészültéig.

## Deployment elv

A fejlesztés külön branchen és PR-ben történik. Először CI, majd staging DB + preview UAT. Production DB és `main` csak külön ellenőrzés és explicit jóváhagyás után módosítható.
