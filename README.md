# A-Hely foglalási rendszer

Az A-Hely saját, magyar nyelvű foglalási és havi elszámolási webalkalmazása.

## Állapot

A projekt az első fejlesztési egységnél tart: a technikai architektúra, az adatmodell és a PostgreSQL-séma alapjai elkészültek. Production használatra még nem alkalmas.

## Kötelező források

- `docs/TECHNIKAI_ARCHITEKTURA_ES_ADATMODELL.md`
- `docs/source/A-Hely_Foglalasi_Rendszer_Funkcionalis_Specifikacio_v1.0.docx`
- `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`

Ellentmondás esetén az aktuális FS és projektkontextus az irányadó.

## Első fejlesztési mérföldkő

1. PostgreSQL-séma és adatbázis-kényszerek
2. Auth és RLS
3. tranzakciós foglalás-létrehozás
4. automatikus adatbázistesztek
5. független review

## Helyi előfeltételek

- Node.js LTS
- pnpm
- Docker
- Supabase CLI

Az alkalmazásváz és a függőségek rögzítése a következő commitban történik; az első commit szándékosan az adatbiztonsági alapokra koncentrál.
