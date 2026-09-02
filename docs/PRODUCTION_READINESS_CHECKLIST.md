# A-Hely foglalási rendszer – Production readiness checklist

Státusz: **részleges funkcionális elfogadás; production NEM GO**. Frissítve: 2026-08-30.

A pipák az alább hivatkozott kódhoz és bizonyítékhoz tartoznak, nem általános engedélyek. Tesztelt alkalmazáskód: `457363609ffac54555a7a17b1cde7742eec5b60e`, PR #90. Forrás: [UAT futási jegyzőkönyv](UAT_FUTASI_JEGYZOKONYV.md) és [bizonyíték-checkpoint](UAT_CHECKPOINT_2026-08-30.md).

A checklist v1.3 helyesbített státusza: 50 tételes PASS, 22 korábbi modul/UI-elfogadás, 1 döntéssel lezárt eset, 22 részleges/tisztázandó bizonyíték és 3 blokkolt production drill. A részletek és a korábbi 59 sor teljes feloldása a [bizonyítékegyeztetésben](UAT_BIZONYITEK_EGYEZTETES_2026-08-30.md) található. A PRICING/MONTH/CSV/SETTLE blokk mind a 17 esete elfogadott. Üres checkbox nem feltétlenül jelent hibát vagy el nem végzett tesztet: a szükséges teljes bizonyíték nincs itt igazolva.

Production deploy csak minden kötelező kapu igazolt teljesülése és külön explicit jóváhagyás után.

## 1. Fejlesztési fázis lezárása

- [x] PR #90 Application CI PASS az elfogadott forrásfán: [#440](https://github.com/ugry65/ahely-booking/actions/runs/33267572656), 86 teszt + typecheck/build.
- [x] PR #90 Database CI PASS az elfogadott forrásfán: [#410](https://github.com/ugry65/ahely-booking/actions/runs/33267572643), 615 pgTAP + 7 konkurencialépés + lint.
- [x] A havi tételes aktív foglalások és a részletes CSV `Foglalás címe` funkciója stagingen megfigyelve (MONTH-05, CSV-03).
- [x] Célzott staging UAT: Tréningterem foglalás címe a tételes havi lekérdezésben látható (MONTH-05).
- [x] Tréningterem default 5 000 Ft/óra és admin egyedi ár: korábbi elfogadás H-02, jelen havi 7 500 Ft-os tétel M-01 (TRAIN-05).
- [x] Befizetések UI scope-döntése korábban elfogadva; az ellenőrzött régi oldal kódja a Havi órákra irányít (PAY-01, R-08). Ez nem új böngészős UAT-PASS.

## 2. Kötelező kritikus regresszió

- [x] Normál foglalás (BOOK-01, H-01).
- [x] Átfedő foglalás blokkolása (BOOK-08, H-01).
- [x] Két egyidejű foglalási kísérletből csak egy sikerül (BOOK-10, A-02 automatikus konkurenciateszt).
- [x] Jogosulatlan helyiségfoglalás tiltásának korábbi CAL-03 elfogadása visszakeresve; backend kontrollt a zöld 003/005 tesztek támogatják (R-01/A-04).
- [ ] 30 perces időegység.
- [x] Minimum 1 órás foglalás (BOOK-03, H-01).
- [x] Előrefoglalási limitek: általános 90 nap és Tréningterem 10 nap (BOOK-07, TRAIN-01).
- [ ] Tréningterem egyéni/csoportos szabályok.
- [x] Tréningterem csoportos default és admin egyedi díj (TRAIN-05/06; H-02, M-01 és A-02).
- [x] Napi/heti ismétlődés, alkalomszám/végdátum, kivétel és konfliktuspolicy (REC-01/03/05–08).
- [ ] Ismétlődő foglalások fennmaradó teljes köre: kétheti/havi, DST és scope-update/cancel bizonyítékok egyeztetése.
- [x] Kivételdátumok (REC-06).
- [x] Sikeres egyszeri módosítás és lemondott booking kizárása a havi elszámolásból (EDIT-01, MONTH-02).
- [x] Saját lemondás 24 órán túli engedése és 24 órán belüli tiltása korábban elfogadva (CANCEL-01/02, R-02).
- [x] Párhuzamos módosítás elavult verziójának elutasítása automatikusan igazolt (EDIT-05, A-04).
- [ ] Módosítás/lemondás további teljes jogosultsági/cutoff/sorozat-scope bizonyítékegyeztetése; EDIT-04 és REC-13 assertion-határ külön jelölve.
- [x] Sávos / progresszív / Fix / Free díjazás, precedencia, effective month, teljes jövőbeli idővonal (PRICING-01–07).
- [x] Havi összesítés és settlement snapshot létrehozás/immutabilitás (MONTH-01–05, SETTLE-01/02).
- [ ] Auditnapló kritikus műveletekre.
- [x] AUTH-01–05 és CAL-01–03 korábbi tételes elfogadása átvezetve; nem új tesztigény.
- [ ] A teljes összetett admin/user és URL/API mátrix lezárási alapja: PR #74/#76/#77 modul-elfogadások már rendelkezésre állnak, nem üres tesztek.

## 3. Adatbiztonsági kapuk

- [ ] Production adatbázis külön a stagingtől.
- [ ] Napi automatikus backup igazoltan aktív.
- [ ] Backup-megőrzés dokumentálva.
- [ ] Elkülönített/off-platform backup megoldás vagy dokumentált alternatíva.
- [ ] Restore eljárás dokumentálva.
- [ ] Restore próba staging/sandbox környezetben ténylegesen végrehajtva és jegyzőkönyvezve.
- [ ] Foglalási és elszámolási adatok restore után konzisztencia-ellenőrzése PASS.
- [ ] Adatmegőrzési szabályok dokumentálva; automatikus végleges törlés nincs admin jóváhagyás nélkül.

## 4. Production konfiguráció

- [ ] Production Supabase secrets és connection stringek kizárólag secretként tárolva.
- [ ] Staging és production környezeti változók nem keverednek.
- [ ] Production hosting/projekt/domain véglegesítve a 2026-08-25-i infrastruktúra-döntés szerint; szolgáltatóválasztást ez a jegyzőkönyv nem hoz.
- [ ] Auth redirect URL-ek és jelszó-visszaállítás production domainre konfigurálva.
- [ ] E-mail küldés production feladóról tesztelve.
- [ ] Admin fiókok és jogosultságok indulás előtt ellenőrizve.
- [ ] Nyilvános önregisztráció tiltva.

## 5. Migráció és rollback

- [ ] Production migrációk dry-run PASS.
- [ ] Production DB deploy csak explicit `PRODUCTION` megerősítéssel.
- [ ] Deploy előtti friss backup/restore pont rendelkezésre áll.
- [ ] Migráció utáni schema/migration status ellenőrzés PASS.
- [ ] Rollback/restore döntési eljárás dokumentálva.
- [ ] Production deploy alatt adatírási kockázat és szükséges karbantartási ablak értékelve.

## 6. UAT / üzleti elfogadás

- [ ] Admin napi naptár teljes folyamat ellenőrizve.
- [ ] Normál user teljes folyamat ellenőrizve.
- [ ] A teljes aktuális mobil/tablet checklist bizonyítékai verzióhoz rendelve. A 2026-08-21-i elfogadott UI-baseline érvényes történeti bizonyíték, nem újraindítandó üres teszt.
- [x] Havi órák és fizetendő összesítő ellenőrizve valószerű mintákkal (MONTH-01–05).
- [x] Tételes aktív foglalások + Foglalás címe ellenőrizve (MONTH-05).
- [x] CSV/export kimenet ellenőrizve; formula-injection automatikus bizonyíték is (CSV-01–03).
- [ ] Lemondási lista és statisztika ellenőrizve.
- [x] A korábbi felhasználó/helyiség/jogosultság-admin modul-UAT elfogadások megőrizve (PR #74/#76/#77); díjazás tételesen PASS.
- [ ] A modul-elfogadások és a teljes mai összetett tesztelvárások bizonyítékhatára a release-döntésben értékelve; nem minden negatív részlépés külön kézi PASS.

## 7. Független review

A [Claude 6 closure](CLAUDE_REVIEW_6_FINAL_CLOSURE_STATUS.md) a PR #91 / `63748919aaa0c2458277536643f79b37efd0bf7c` verzióra lezárt funkcionális/dokumentációs review-t rögzít. Ez megőrzendő eredmény, nem újra nyitott régi finding. Az azóta változott kódra és a végleges production megoldásra nincs itt külön review-bizonyíték; a lentiek release-szintű kapuk.

Kritikus részeknél külön második reviewer szükséges:

- [ ] foglalási motor és dupla foglalás elleni védelem;
- [ ] jogosultságok / RLS / SECURITY DEFINER függvények;
- [ ] adatmodell;
- [ ] díjszámítás és settlement snapshot;
- [ ] backup és restore stratégia;
- [ ] production deploy és rollback terv.

## 8. Monitoring és alert kapu

A kanonikus baseline és a 2026-08-25-i infrastruktúra-döntés szerint:

- [ ] Külső uptime/heartbeat és biztonságos alkalmazás + DB health-check működik.
- [ ] Válaszidő/hibaarány és backup-frissesség figyelése igazolt.
- [ ] Kontrollált hiba tényleges riasztást vált ki; a recovery értesítés is megérkezik.
- [ ] A drill eredménye és az üzemeltetési felelősség dokumentált (PROD-03).

## 9. Go-live kapu

Production csak akkor indulhat, ha:

1. minden blokkoló CI/UAT hiba lezárt;
2. backup és tényleges restore próba bizonyított;
3. kritikus független review lezárt;
4. production konfiguráció ellenőrzött;
5. monitoring/heartbeat, alert és recovery drill bizonyított;
6. explicit üzleti jóváhagyás megtörtént.

A `main` branch production előtt csak review-zott és stagingen elfogadott állapotot tartalmazhat.
