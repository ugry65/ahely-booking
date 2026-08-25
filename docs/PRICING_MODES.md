# User-szintű díjazási módok

Állapot: elfogadott üzleti döntés, 2026-08-25. Kapcsolódó issue: #82.

## Támogatott módok

1. `Sávos` (`tiered`) – **alapértelmezett**.
   - A havi összes elszámolandó normál óraszám alapján egyetlen sáv kerül kiválasztásra.
   - A kiválasztott sáv óradíja a teljes havi normál óraszámra vonatkozik.
   - Példa: 20 óra esetén 20 × 1 900 Ft = 38 000 Ft.
2. `Progresszív` (`progressive`).
   - A díjsávok egymás után csak a saját tartományuk óráira vonatkoznak.
   - Példa: 20 óra esetén 15 × 2 700 Ft + 5 × 1 900 Ft = 50 000 Ft.
3. `Free` (`free`).
   - A user minden foglalása 0 Ft, beleértve a Tréningtermet és annak speciális díjazását is.
   - A foglalások és óraszámok ettől még megmaradnak riportálási célra.

## Mi számít elszámolandó foglalásnak

Csak az aktív, a foglalási rendszerben ténylegesen meglévő foglalás számlázódik. A törölt/lemondott foglalás nem növeli a havi óraszámot és nem kerül a fizetendő összegbe.

## Érvényesség és történet

- A díjazási mód userenként időben verziózott.
- Egy díjazási mód egy teljes havi elszámolási időszakra érvényes, ezért az érvényesség kezdete hónap első napja.
- Korábbi, már lezárható/lezárt hónapra a mód nem dátumozható vissza az admin RPC-n keresztül.
- Jövőbeli mód előre rögzíthető.
- Azonos jövőbeli kezdőhónaphoz tartozó terv később módosítható; minden tényleges változás auditálódik.
- Explicit beállítás hiányában a rendszer `Sávos` módot alkalmaz.

## Adatmodell

A meglévő `pricing_tiers`, `user_price_overrides`, `special_room_rates`, `monthly_settlements`, `settlement_revisions` és `settlement_booking_lines` táblák megmaradnak.

A user díjazási módját a külön `user_pricing_policies` tábla tárolja. Ez csak a számítás módját választja ki; az árlistát nem duplikálja.

## Biztonság

- Közvetlen Data API írás a `user_pricing_policies` táblára tiltott.
- Módosítás kizárólag aktív admin által hívható `admin_set_user_pricing_policy` RPC-n történhet.
- Minden változás `audit_logs` rekordot hoz létre.
- A belső effektív módot meghatározó függvény közvetlenül nem hívható `authenticated` szerepkörből.

## Következő fejlesztési egység

A következő fázis a központi havi díjszámító backend/DB logika:
- sávos nem progresszív számítás;
- progresszív számítás;
- Free 0 Ft;
- Tréningterem speciális szabályok;
- törölt foglalások kizárása;
- ugyanazon számítás használata dashboard és settlement esetén.
