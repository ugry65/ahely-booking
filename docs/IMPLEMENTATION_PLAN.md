> **Aktuális megvalósítási státusz – 2026-09-25:** A generic AllBooked write-import stagingen valós 35 bookingos importtal E2E igazolt; a Notes-megőrzés, Tréningterem-besorolási UX, import readiness és migrációs oldal layout javításai mainben vannak. Az Admin → Havi órák összesítő valódi XLSX exportja elkészült (PR #190). A következő launch-kritikus munka nem új foglalási feature, hanem production release-gate: aktuális backup/restore bizonyíték, production DB migration chain, booking-email aktiválási kapu és release candidate egyezés. Részletek: [PROJECT_STATUS_2026-09-25.md](PROJECT_STATUS_2026-09-25.md).

> **Aktuális megvalósítási státusz – 2026-09-24:** A dokumentum alábbi backlog-fejezetei történeti sorrendet őriznek. A 7. „Díjszámítás” már nem későbbi fázis: PR #179–#184 után mainben és stagingen implementált, célzott UAT-ja 12/12 PASS. A booking e-mail outbox/worker PR #175–#177-tel mainbe integrált; stagingen a DB-elemek telepítve és korábbi valódi Resend create/update/cancel UAT PASS, de normál staging üzemben nincs szándékos valós küldés, production aktiválás külön release-gate. A korábbi teljes foglalási UAT elfogadásai érvényben maradnak; változatlan funkciókat nem kell újrafuttatni. A production release továbbra is külön jóváhagyás-, backup/restore-, migráció- és e-mail-aktiválási kapukhoz kötött.

> **Dokumentum státusza – 2026-09-17:** Ez a backlog történeti fejlesztési pillanatképe. A benne szereplő régi commit-, issue- és release-gate állapotok nem mindenütt tükrözik a jelenlegi `main` állapotát. Aktuális forrás: a `main` branch és az aktuális auditdokumentáció. A teljes funkcionális UAT és a production release-gate továbbra is külön, bizonyíték-alapú lezárást igényel. A PR #163 (AllBooked import) és PR #164 (Supabase availability health-check) már merge-elve van; ezek állapotát a jelenlegi audit dokumentálja. Történeti fejezetek tartalma változatlanul megőrzendő.

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

Állapot: **implementálva és staging UAT-val elfogadva** (Issue #178, PR #179–#184; 2026-09-24: 12/12 célzott regressziós UAT PASS). A havi összesítő/részletező és export snapshot-aware pricing réteget használ; a történeti legacy Tréningterem-díj megőrzése regresszióvédett kompatibilitási követelmény.

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

Állapot: helyiség- és hozzáférés-adminfelület, havi óraszám-adminnézet, CSV-export és az elszámolási összesítés valódi XLSX exportja implementálva. A teljes pénzügyi admin (befizetések/korrekciók) továbbra is későbbi fázis.

- userek, helyiségek, jogok és beállítások;
- havi elszámolás és részletek;
- összesítő XLSX implementálva; részletes/stabil pénzügyi XLSX és további pénzügyi mezők a teljes pénzügyi modul részeként későbbi fázis;
- export revision-manifeszt és SHA-256.

## 11. E-mail, naplózás és adatmegőrzés

Állapot: booking e-mail outbox/worker és megfigyelhetőség mainben implementálva (PR #175–#177); staging DB telepítve, korábbi valós Resend create/update/cancel UAT PASS. Production DB-migráció és send aktiválás külön jóváhagyás nélkül tilos. Az adatmegőrzési további elemek külön státuszúak.

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