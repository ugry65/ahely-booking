> **Dokumentum státusza – 2026-09-18:** Ez a fájl UAT-futási jegyzőkönyv-sablon és történeti nyilvántartás. Az üres mezők és a `NEM FUTOTT` értékek azt jelentik, hogy ebben a dokumentumban nincs rögzített manuális UAT-bizonyíték; automatikus CI-tesztek ezt nem helyettesítik. A dokumentumot csak tényleges, környezethez, commit SHA-hoz és tesztelőhöz kötött manuális UAT után szabad PASS/elfogadási állapotra frissíteni. A kapcsolódó checklist marad az UAT elsődleges tesztforrása.

# A-Hely foglalási rendszer – UAT futási jegyzőkönyv

Kapcsolódó checklist: `docs/FUNKCIONALIS_UAT_CHECKLIST.md`

Kapcsolódó issue: #32

## Futás adatai

- Dátum:
- Környezet:
- Alkalmazás commit SHA:
- Tesztelő:
- Böngésző/eszköz:

## Összesítés

- Sikeres:
- Hibás:
- Blokkolt:
- Nem futott:
- Nyitott P1:
- Nyitott P2:
- Nyitott P3:

## Teszteredmények

| Teszteset | Státusz | Megjegyzés | GitHub issue |
| --- | --- | --- | --- |
| UAT-AUTH-01 | NEM FUTOTT | | |
| UAT-AUTH-02 | NEM FUTOTT | | |
| UAT-AUTH-03 | NEM FUTOTT | | |
| UAT-AUTH-04 | NEM FUTOTT | | |
| UAT-AUTH-05 | NEM FUTOTT | | |
| UAT-CAL-01 | NEM FUTOTT | | |
| UAT-CAL-02 | NEM FUTOTT | | |
| UAT-CAL-03 | NEM FUTOTT | | |
| UAT-CAL-04 | NEM FUTOTT | | |
| UAT-BOOK-01 | NEM FUTOTT | | |
| UAT-BOOK-02 | NEM FUTOTT | | |
| UAT-BOOK-03 | NEM FUTOTT | | |
| UAT-BOOK-04 | NEM FUTOTT | | |
| UAT-BOOK-05 | NEM FUTOTT | | |
| UAT-BOOK-06 | NEM FUTOTT | | |
| UAT-BOOK-07 | NEM FUTOTT | | |
| UAT-BOOK-08 | NEM FUTOTT | | |
| UAT-BOOK-09 | NEM FUTOTT | | |
| UAT-BOOK-10 | NEM FUTOTT | automatizált bizonyíték | |
| UAT-BOOK-11 | NEM FUTOTT | | |
| UAT-TRAIN-01 | NEM FUTOTT | | |
| UAT-TRAIN-02 | NEM FUTOTT | | |
| UAT-TRAIN-03 | NEM FUTOTT | | |
| UAT-TRAIN-04 | NEM FUTOTT | | |
| UAT-EDIT-01 | NEM FUTOTT | | |
| UAT-EDIT-02 | NEM FUTOTT | | |
| UAT-EDIT-03 | NEM FUTOTT | | |
| UAT-EDIT-04 | NEM FUTOTT | | |
| UAT-EDIT-05 | NEM FUTOTT | | |
| UAT-CANCEL-01 | NEM FUTOTT | | |
| UAT-CANCEL-02 | NEM FUTOTT | | |
| UAT-CANCEL-03 | NEM FUTOTT | | |
| UAT-CANCEL-04 | NEM FUTOTT | | |
| UAT-REC-01 | NEM FUTOTT | | |
| UAT-REC-02 | NEM FUTOTT | | |
| UAT-REC-03 | NEM FUTOTT | | |
| UAT-REC-04 | NEM FUTOTT | | |
| UAT-REC-05 | NEM FUTOTT | | |
| UAT-REC-06 | NEM FUTOTT | | |
| UAT-REC-07 | NEM FUTOTT | | |
| UAT-REC-08 | NEM FUTOTT | | |
| UAT-REC-09 | NEM FUTOTT | automatizált bizonyíték + célzott UAT | |
| UAT-ADMIN-01 | NEM FUTOTT | | |
| UAT-ADMIN-02 | NEM FUTOTT | | |
| UAT-ADMIN-03 | NEM FUTOTT | | |
| UAT-ADMIN-04 | NEM FUTOTT | | |
| UAT-ADMIN-05 | NEM FUTOTT | | |
| UAT-ADMIN-06 | NEM FUTOTT | | |
| UAT-ADMIN-07 | NEM FUTOTT | | |
| UAT-ADMIN-08 | NEM FUTOTT | | |
| UAT-MONTH-01 | NEM FUTOTT | | |
| UAT-MONTH-02 | NEM FUTOTT | | |
| UAT-MONTH-03 | NEM FUTOTT | | |
| UAT-MONTH-04 | NEM FUTOTT | | |
| UAT-CSV-01 | NEM FUTOTT | | |
| UAT-CSV-02 | NEM FUTOTT | automatizált bizonyíték | |
| UAT-UX-01 | NEM FUTOTT | | |
| UAT-UX-02 | NEM FUTOTT | | |
| UAT-UX-03 | NEM FUTOTT | | |
| UAT-UX-04 | NEM FUTOTT | | |

## Funkcionális gap-döntések

| Téma | Döntés | Prioritás / issue |
| --- | --- | --- |
| Admin más user foglalásának módosítása/törlése UI-ból | KÓDSZINTEN RENDELKEZÉSRE ÁLL; célzott manuális UAT még szükséges | |
| Admin más user számára történő foglalás | SZÜKSÉGES ÉS IMPLEMENTÁLT; célzott manuális UAT-bejegyzés szükséges | |
| Heti nézet szükséges-e a Skedda kiváltásához | NEM BLOKKOLÓ az első éles verzióban; napi nézet elegendő | |
| E-mail visszaigazolás szükséges-e az első éles verzióhoz | IGEN; korábban tesztelve a projektgazda szerint, külön dokumentált ellenőrzés szükséges | |
| Hiányzó admin központi beállítások | JELENLEG NINCS ISMERT HIÁNYZÓ KÖZPONTI BEÁLLÍTÁS | |

## Aktuális scope- és bizonyítékállapot

A fenti döntések a projektgazda 2026-09-18-i megerősítése alapján kerültek rögzítésre. Ez a döntésfrissítés nem helyettesíti a még üres manuális UAT-sorok tényleges kitöltését; a manuális futásokat továbbra is környezethez, commit SHA-hoz és tesztelőhöz kötött bizonyítékkal kell lezárni.

## Elfogadási döntés

- [ ] Funkcionálisan alkalmas a Skedda kiváltására.
- [ ] Még nem alkalmas; P1/P2 javítás szükséges.

Indoklás / megjegyzés:
