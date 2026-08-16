# ADR-0001: Moduláris monolit Next.js + Supabase alapon

- Dátum: 2026-08-16
- Állapot: elfogadott fejlesztési alap

## Döntés

Next.js/TypeScript moduláris monolitot használunk Supabase Auth-tal és menedzselt PostgreSQL-lel. Kritikus írások tranzakciós adatbázis-függvényen keresztül, RLS és adatbázis-kényszerek mellett történnek.

## Miért

Az A-Hely célalkalmazásához a microservice-architektúra szükségtelen üzemeltetési terhet adna. A PostgreSQL natív tartomány- és kizárási kényszere megbízhatóan kezeli a párhuzamos foglalási versenyhelyzetet. A Supabase az Auth, RLS és menedzselt backup alapját egy rendszerben biztosítja.

## Következmények

- Előny: kevés komponens, egy tranzakciós adatforrás, egyszerűbb audit és riport.
- Előny: később önálló PostgreSQL/Next.js környezetbe migrálható.
- Kockázat: a kritikus SQL-függvények magas színvonalú DB-tesztet és review-t igényelnek.
- Költség: production PITR és elkülönített mentés fizetős üzemeltetési elem.
