# UAT eredmények – bizonyítékjegyzék

Állapot-egyeztetés: 2026-09-18. Elsődleges aktuális státusz: [RELEASE_EVIDENCE.md](RELEASE_EVIDENCE.md).

## Korábban elfogadott eredmények

A main korábbi üres sablonja nem a teljes projekt tesztállapota volt. A korábbi elfogadásokat tartalmazó [staging jegyzőkönyv](evidence/2026-09-18-staging/UAT_FUTASI_JEGYZOKONYV.md) és [checkpoint](evidence/2026-09-18-staging/UAT_CHECKPOINT_2026-08-30.md) változatlan másolata megőrzésre került.

Az augusztus 30-i összesítés: **50 PASS, 22 modul-elfogadás, 1 döntéssel lezárt, 22 bizonyíték-egyeztetendő és 3 akkori production blokk**. Ez történeti állapot. A 22 egyeztetendő sor nem 22 új teszt; a korábbi production blokkokat későbbi bizonyítékok nélkül nem szabad jelenleg nyitottnak minősíteni.

## Projektgazdai megerősítés – 2026-09-18

Imre megerősítette: kapott e-mailt; tesztelték a foglalást, módosítást, törlést/lemondást, ismétlődést és annak módosítását, és a kipróbált lépések működtek. Ez felhasználói elfogadási forrás. Nem társítunk hozzá utólag kitalált commit SHA-t, futási dátumot vagy teljes tesztmátrixot.

A Resend create/update/cancel kézbesítés külön [jegyzőkönyvben](evidence/2026-09-18-staging/BOOKING_EMAIL_RESEND_STAGING_UAT.md) is igazolt. Az ismétlődési capture és a valódi kézbesítés eltérő bizonyítéktípus.

## Már eldöntött követelmények

- Booking e-mail az első éles verzióban kötelező.
- Admin más aktív user nevében foglalhat.
- A heti nézet nem első élesítési blokkoló.
- Jelenleg nincs projektgazda által jelzett hiányzó központi adminbeállítás.
- Az együgyfeles import megvan; a többügyfeles import külön fejlesztés.

## Következő ellenőrzés határa

A stagingen elfogadott funkciók mainbe integrálását és a tényleges éles verziót kell igazolni. Teljes kézi UAT nem írható elő pusztán régi üres sablon, hiányzó kattintási napló vagy dokumentációs commit miatt. Konkrét regresszióhoz célzott ellenőrzés szükséges.

A történeti eredmények nem jelentik automatikusan a jelenlegi production deployment elfogadását. A nyitott kiadási lépések és forrásverziók a RELEASE_EVIDENCE dokumentumban vannak.
