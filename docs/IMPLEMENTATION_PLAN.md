# Implementációs backlog

Az issue-k sorrendje függőségi sorrend. Kritikus issue csak automatikus teszt és független review után zárható.

## 1. Adatbázis-alap és ütközéskényszer

Állapot: implementálva, CI-validálás alatt.

- teljes kezdeti séma migrációja;
- induló helyiségek és díjak seedje;
- aktív foglalások GiST exclusion constraintje;
- 30 perces rács és minimum 60 perc DB-kényszere;
- append-only audit alap;
- pgTAP regressziós tesztek.

Elfogadás: friss adatbázison migráció és minden DB-teszt sikeres, beleértve az átfedés elutasítását.

## 2. Auth, profil és RLS

Állapot: implementálva, CI-validálásra vár.

- admin által indított meghívás;
- bejelentkezés, kijelentkezés, jelszó-visszaállítás;
- profil és adminszerep;
- deny-by-default RLS-policyk;
- közvetlen URL/API jogosultsági tesztek.

## 3. Helyiségek és hozzáférések

Állapot: helyiség- és jogosultság-adminisztráció, névláthatóság, közös effektív helyiségjog és admin felhasználói felület implementálva (Issue #25, PR #26).

- admin helyiség CRUD deaktiválással;
- közvetlen és csoportos userjog;
- foglalási és ismétlési engedély;
- névláthatósági maszkolás.

## 4. Tranzakciós egyedi foglalás

Állapot: implementálva.

- szerveroldali validáció;
- adatbázis RPC;
- nyitvatartás és kivételdátum;
- előrefoglalási limitek;
- Tréningterem 10 nap és használattípus;
- idempotencia, audit és e-mail outbox;
- két valóban párhuzamos kérés integrációs tesztje.

## 5. Foglalás módosítása és lemondása

Állapot: implementálva.

- teljes újraellenőrzés módosításkor;
- user 24 órás tiltás;
- admin törlés;
- lemondási snapshot és statisztika;
- elszámolásból kizárási szabály a jóváhagyott üzleti döntés alapján.

## 6. Ismétlődő foglalás

Állapot: tranzakciós adatbázis-RPC, regressziós/konkurenciatesztek és normál user felület implementálva (Issue #17, #23).

- napi, heti, kétheti, havi;
- végdátum/darabszám és kivételdátum;
- `abort_all` és `create_available` konfliktuspolitika;
- Tréningterem ismétlés csak adminnak.

## 7. Díjszámítás

Állapot: későbbi fázisra halasztva. Az előtte jóváhagyott havi óraszám-kimutatás és CSV-export implementálva (Issue #27, PR #28), díj- vagy pénzügyi számítás nélkül.

- verziózott sávos és egyedi díjak;
- teljes havi normál óraszám alapján egységes sáv;
- Tréningterem csoportos külön tétel;
- immutable settlement revision és input hash;
- összes FS szerinti határérték- és sávváltásteszt.

## 8. Befizetés és korrekció

Állapot: későbbi fázisra halasztva a backup/restore baseline és production adatvédelmi réteg után.

- részfizetés;
- fizetési mód és célhely;
- automatikus egyenlegszámítás;
- admin státusz;
- kötelező indokú, auditált korrekció.

## 9. Naptár és user felület

Állapot: napi többhelyiséges naptár, egyedi foglalási űrlap, saját foglalások módosítása/lemondása és ismétlődő foglalási felület implementálva; a heti nézet későbbi szelet.

- magyar napi többhelyiséges nézet;
- heti nézet;
- mobil/tablet használhatóság;
- saját foglalás kiemelése;
- Foglalásaim és opcionális havi dashboard.

## 10. Adminfelület és XLSX

Állapot: helyiség- és hozzáférés-adminfelület, valamint havi óraszám-adminnézet és CSV-export implementálva; teljes pénzügyi admin és XLSX későbbre halasztva.

- userek, helyiségek, jogok és beállítások;
- havi elszámolás és részletek;
- stabil összesítő és részletes XLSX;
- export revision-manifeszt és SHA-256.

## 11. E-mail, naplózás és adatmegőrzés

- outbox worker és retry;
- visszaigazolások;
- technikai hibalista;
- 2 éves jelölés és 30/15/5/1 napos figyelmeztetés;
- admin jóváhagyás nélküli végleges törlés tiltása.

## 12. Backup/restore és release

Állapot: a backup/restore technikai baseline és runbook készül. A cél a pénzügyi modul előtt napi, elkülönített logikai backup és bizonyított restore-folyamat kialakítása.

- productionhöz menedzselt napi adatbázis-backupot biztosító Supabase csomag;
- elkülönített, titkosított napi logikai backup;
- 35 napos napi és 13 hónapos havi off-site retention;
- manifest és SHA-256 integritásellenőrzés;
- restore runbook és próbajegyzőkönyv;
- külön staging/restore célkörnyezet;
- production indulás előtt sikeres teljes restore-drill;
- PITR opcionális későbbi erősítés külön költség-/kockázatdöntéssel;
- teljes FS elfogadási teszt;
- független kritikus review;
- staging jóváhagyás, majd production.
