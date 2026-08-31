# Döntés – Production backup retention és Backblaze B2 Object Lock

Dátum: 2026-08-31
Kapcsolódó issue-k: #100, #101
Státusz: ELFOGADOTT ÜZLETI/ÜZEMELTETÉSI DÖNTÉS

## Elfogadott retention

- 0–14 nap: mind a napi négy (08:00, 12:00, 16:00, 20:00 Europe/Budapest) sikeres restore-pont megmarad.
- 15–90 nap: naponként egy restore-pont marad meg.
- 3–24 hónap: havonta egy restore-pont marad meg.
- 24 hónapnál régebbi automatikus megőrzés nem része az induló policy-nak.

A napi ritkításnál az adott Europe/Budapest szerinti nap legutolsó sikeres backupja marad meg. A havi ritkításnál az adott hónap legutolsó sikeres backupja marad meg.

## Backblaze B2 Object Lock

- A production backup bucket Object Lock védelemmel működjön.
- Induló retention mód: Governance.
- Minimális Object Lock időtartam: 30 nap.
- Compliance mód induláskor nem használatos, mert annak visszafordíthatatlansága szükségtelen üzemeltetési kockázatot okozna.

## Biztonsági invariánsok

1. 30 napos lock alatt automatikus törlés nem történhet.
2. A retention script csak a lock lejárta után ritkíthat B2 objektumot.
3. Google Drive és B2 retention logikája azonos restore-pont készletre törekszik, de B2 a törlésvédett biztonsági példány.
4. Törlés/ritkítás alapértelmezetten dry-run legyen; éles törlés csak explicit módon engedélyezhető.
5. Hibás vagy hiányos fájlnév/metadata esetén a script fail-closed módon ne töröljön.
6. A legutóbbi 14 nap teljes, napi 4× restore-pont készlete nem ritkítható.
7. A retention folyamat nem írhat felül backup artifactot.
8. Production aktiválás előtt a retention logikának automatikus teszttel és sandbox dry-runnal bizonyítottnak kell lennie.

## Költség és felülvizsgálat

A policy célja, hogy a rövid távú visszaállíthatóság erős maradjon, miközben a hosszabb távú tárolási mennyiség kontrollált. A tényleges backup méret és B2/Google Drive fogyasztás alapján a policy később felülvizsgálható, de a megőrzési idő csökkentése külön üzleti döntést igényel.
