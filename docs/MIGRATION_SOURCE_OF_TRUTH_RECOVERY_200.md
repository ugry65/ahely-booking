# Migration source-of-truth helyreállítás – #200

## Miért kell
A 2026-09-25-i read-only release audit kimutatta, hogy a `main` migration könyvtárból hiányzott több, stagingen már alkalmazott történeti migráció. A későbbi admin pricing migráció ezekre az objektumokra épít, ezért a hiányos lánc productionre nem telepíthető biztonságosan.

## Visszaemelt kanonikus történeti forrás
A branch 23 hiányzó történeti migration fájlt állít vissza:
- `202608250001..202608250015`: pricing / monthly settlement / payment baseline és hardening;
- `202608260001..202608260002`: pricing policy + settlement immutability hardening;
- `20260826205749`: closed settlement line insert protection;
- `20260829145720`: admin past-booking creation;
- `20260830183000`: booking update cutoff guard;
- `202609040001`, `202609050001`, `202609050002`: first-login/password/admin temporary-password audit hardening.

Ezeket nem rekonstruáltuk üzleti logikából. A 20260825/26/29/30 fájlok Git blob SHA-ja megegyezik a `feature/82-pricing-modes` eredeti végleges forrásával; a 20260904/05 fájloké a `feature/107-booking-email-outbox` eredeti forrásával.

## Staging history → kanonikus Git mapping
A staging migration history nem mindenhol ugyanazt a timestampet használja, mint a kanonikus Git-fájlnév. Ezek **mapping eltérések**, nem automatikusan újrajátszandó migrációk.

- staging `20260923171023 admin_pricing_and_booking_rate_override`
  → kanonikus `20260922160000_admin_pricing_and_booking_rate_override.sql`;
- staging `20260924080123 preserve_legacy_training_booking_rate`
  → nincs külön történeti migration fájl; a változás a fenti kanonikus migration Git-fejlődéséből származik, különösen a `0e075b8` és `979d703` commitokból;
- staging `20260924181855 allbooked_preserve_booking_notes`
  → kanonikus `20260924183000_allbooked_preserve_booking_notes.sql`;
- staging `20260925095053 booking_email_recurring_summary`
  → kanonikus `20260925100000_booking_email_recurring_summary.sql`.

A staging history timestampjeit ezért nem szabad külön migration fájlként mesterségesen létrehozni vagy productionre vakon replayelni.

## Legacy Tréningterem kompatibilitás
A branch új, előre mutató kompatibilitási migrációja:
`20260925143000_retire_empty_legacy_training_rate.sql`.

Ez **nem történeti fájl rekonstrukciója**. Célja, hogy a visszaállított teljes lánc tiszta adatbázison a jelenlegi modellt adja, miközben deployed adatbázison megőrzi a történeti Tréningterem-díjakat:
- ha a legacy `group_hourly_rate_huf` oszlopban nincs történeti érték, a legacy write-path és az oszlop eltávolítható;
- ha legalább egy történeti érték van, a migráció fail-closed módon megtartja a compatibility surface-t;
- a resolver sorrendje ilyen deployed lineage esetén: booking override → történeti booking-szintű Tréningterem-díj → user override → aktuális Tréningterem alapdíj → központi sáv.

A `112_legacy_training_rate_compatibility.sql` regressziós teszt mindkét adatfüggő ágat és a precedence láncot explicit lefedi.

## Staging drift audit – 2026-09-25
Read-only ellenőrzés a staging projekten (`fvwapntzhavhgazeflri`):
- a teljes 202608250001..20260830183000 pricing/settlement baseline history alkalmazva van;
- a 202609040001/202609050001/202609050002 auth hardening alkalmazva van;
- a pricing scheme type, user pricing policy table, havi pricing és applied-rate resolver jelen van;
- a booking override oszlop jelen van;
- a legacy `group_hourly_rate_huf` oszlop jelen van és **42 nem-null történeti értéket** tartalmaz;
- a hozzá tartozó legacy trigger és admin/trigger függvények jelen vannak.

Következmény: stagingen a `20260925143000` forward migration adatmegőrző ága a helyes ág; a 42 történeti érték miatt nem szabad a legacy oszlopot vagy write-pathot eltávolítani. Ez összhangban van a korábbi staging UAT-tal.

## Automatikus ellenőrzés
A PR pristine 0→HEAD rebuildje és a teljes DB tesztcsomag a compatibility teszt hozzáadása előtti HEAD-en PASS volt. Az új compatibility tesztet tartalmazó HEAD-en a Release evidence PASS; a Database tests futása kötelező merge gate, és csak sikeres lezárása után tekinthető a branch merge-késznek.

## Független review
A kritikus pénzügyi migration láncot független Claude-review ellenőrizte. Eredmény: **APPROVE**, BLOCKER nélkül. A reviewer által jelzett legacy compatibility teszthiányokat a `112_legacy_training_rate_compatibility.sql` zárja le.

## Production foglalási adatindítás – owner döntés 2026-09-25
Productionre **nem kerülhet át staging foglalási adat**. A staging kizárólag teszt/UAT környezet; annak foglalásai, audit- és elszámolási mellékhatásai nem production seed adatok.

A production indulási invariant:
- a valódi migráció megkezdése előtt a production `bookings` tábla üzleti értelemben tiszta;
- a productionbe kerülő első valódi foglalások kizárólag a külön jóváhagyott éles migrációs forrásból vagy az éles rendszerben létrehozott foglalásokból származhatnak;
- stagingből sem közvetlen DB-másolás, sem backup/restore, sem seed/import nem vihet át foglalási rekordot;
- a foglalásokhoz kapcsolódó settlement/payment/audit/outbox adatoknál ugyanezt a környezetszétválasztást kell betartani;
- production preflight kötelezően ellenőrzi a foglalási táblát és a kapcsolódó üzleti adatokat.

A 2026-09-25-i read-only production ellenőrzés **21 meglévő booking rekordot** talált. Emiatt a „tiszta foglalási tábla” feltétel jelenleg nem tekinthető teljesültnek. Ezeket nem töröljük automatikusan: production adat törlése külön, explicit owner approvalt és előtte mentést/azonosítást igényel.

## Production release terv – írás nélkül
Production DB módosítás csak külön owner approval után történhet. Addig kizárólag read-only preflight engedélyezett.

Kötelező preflight:
1. friss production migration history snapshot;
2. pricing-scheme type/table/function jelenlétének újbóli ellenőrzése;
3. production booking rekordok eredetének és darabszámának ellenőrzése; a valódi migráció előtt elvárt tiszta állapot külön release gate;
4. booking override és legacy Training-rate oszlopok/értékek újbóli ellenőrzése;
5. Trainingterem történeti és aktív booking/rate adatok ellenőrzése;
6. pricing tier és special-room-rate állapot összevetése a tervezett post-migration állapottal;
7. dry-run/diff alapján a várható DDL és adatváltozások tételes ellenőrzése;
8. destruktív vagy nem várt művelet esetén fail closed;
9. production write előtt friss backup + restore/restore-drill bizonyíték;
10. csak ezután külön explicit owner approval;
11. deploy után migration history, schema fingerprint, pricing regresszió és booking smoke test.

## Fennmaradó kapuk
- az új HEAD Database tests eredménye legyen PASS;
- production read-only dry-run/preflight terv bizonyítsa, hogy nincs hiányzó dependency vagy váratlan destruktív lépés;
- friss backup/restore evidence legyen meg a későbbi production write előtt;
- külön owner approval production DB deploy előtt.

Productiont ez a branch nem módosítja.
