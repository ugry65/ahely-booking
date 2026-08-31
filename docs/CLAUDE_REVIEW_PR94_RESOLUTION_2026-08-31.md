# PR #94 független Claude-review – feloldás

Dátum: 2026-08-31
PR: #94 – Fix 24h booking update cutoff and prove scope rollback

## Review eredmény

A független Claude-review nem talált BLOCKING hibát.

IMPORTANT I-1: az `auth.uid() IS NULL` trusted service/internal bypass ág explicit regressziós tesztje hiányzott.

MINOR M-1: jövőbeli kombinált `status` + időmező UPDATE esetén robusztusabb, ha a trigger csak az eredeti `OLD.status = 'active'` állapotot követeli meg.

M-2 redundáns belső status guard, nem igényel javítást.

M-3 külön későbbi occurrence-cutoff rollback teszt hiánya nem blokkoló, mert az uncaught exception miatti teljes tranzakciós rollbacket a későbbi occurrence collision teszt már bizonyítja.

## Elvégzett javítások

- I-1 lezárva külön `102_booking_update_cutoff_service_bypass.sql` pgTAP teszttel:
  - explicit bizonyítja, hogy a teszt `auth.uid() IS NULL` kontextusban fut;
  - explicit bizonyítja, hogy a trusted service/internal közvetlen UPDATE cutoffon belül sikeres;
  - ellenőrzi, hogy a módosítás ténylegesen eltárolódik.
- M-1 defensive hardening elkészült:
  - a trigger `WHEN` feltétele az eredeti `OLD.status = 'active'` állapotot használja;
  - a triggerfüggvény ugyanezt az eredeti állapotot védi, ezért jövőbeli kombinált status+mező UPDATE sem tudja a cutoff guardot a `NEW.status` megváltoztatásával kikerülni.
- M-2 és M-3 dokumentáltan nem igényel további változtatást.

## Automatikus bizonyíték

GitHub Actions `Database tests` #418, head `d58d4499d72243643375c85562cc1a4af23ca263`: SUCCESS.

PASS:
- migrations + seed rebuild;
- teljes pgTAP adatbázis tesztcsomag, benne az új service/internal bypass teszttel;
- booking concurrency;
- booking mutation concurrency;
- room access concurrency;
- recurring booking concurrency;
- last-admin guard concurrency;
- calendar color concurrency;
- repeat-permission compatibility concurrency;
- schema lint.

A későbbi dokumentációs commitok nem módosítják a tesztelt adatbázis-kódot.

## Következtetés

A független review IMPORTANT findingja lezárt, a javasolt defensive hardening elkészült, a kritikus DB-regresszió teljes CI-n zöld. PR #94 technikailag integrálható a `feature/82-pricing-modes` integration branch-be. Ez nem main merge és nem production deploy.
