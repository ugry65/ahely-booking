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

Állapot: későbbi fázisra halasztva a funkcionális UAT és a production adatvédelmi réteg után.

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

## 12. Teljes funkcionális UAT a Skedda kiváltása előtt

Állapot: **aktuális fejlesztési fázis** (Issue #32).

A felhasználói döntés alapján a backup/restore stratégiai baseline után, de a tényleges production backup automatizálás előtt teljes funkcionális elfogadási teszt következik. A cél annak bizonyítása, hogy a napi foglalási működés végponttól végpontig alkalmas a Skedda kiváltására.

- `docs/FUNKCIONALIS_UAT_CHECKLIST.md` alapján manuális böngészős UAT;
- meglévő Vitest/pgTAP/konkurenciatesztek összevetése a checklisttel;
- belépés és jogosultságok;
- napi naptár és mobil/tablet használhatóság;
- egyedi foglalás, módosítás, lemondás;
- átfedés és konkurencia;
- Tréningterem szabályok;
- ismétlődő foglalások;
- admin user/helyiség/hozzáférés folyamatok;
- havi óraszám és CSV-export;
- minden funkcionális eltérés külön issue-ba kerül P1/P2/P3 besorolással.

Kilépési feltétel: nincs nyitott P1/P2 funkcionális hiba, és a kritikus napi folyamatok manuálisan valamint az elérhető automatikus tesztekkel is igazoltak.

## 13. Backup/restore és release

Állapot: a backup/restore technikai baseline elkészült (Issue #29, PR #30). A tényleges production backup automatizálás **a funkcionális UAT után folytatódik**.

- productionhöz menedzselt napi adatbázis-backupot biztosító Supabase csomag;
- elkülönített, titkosított napi logikai backup;
- 35 napos napi és 13 hónapos havi off-site retention;
- manifest és SHA-256 integritásellenőrzés;
- restore runbook és próbajegyzőkönyv;
- külön staging/restore célkörnyezet;
- production indulás előtt sikeres teljes restore-drill;
- PITR opcionális későbbi erősítés külön költség-/kockázatdöntéssel;
- független kritikus review;
- staging jóváhagyás, majd production.

A production kapu változatlan: tényleges backup és sikeres restore-drill nélkül a rendszer nem élesíthető.