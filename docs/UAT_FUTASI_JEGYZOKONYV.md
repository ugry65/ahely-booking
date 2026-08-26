# A-Hely foglalási rendszer – UAT futási jegyzőkönyv

Checklist verzió: 1.1
Kapcsolódó checklist: `docs/FUNKCIONALIS_UAT_CHECKLIST.md`
Kanonikus baseline: `docs/CURRENT_FUNCTIONAL_BASELINE.md`
Kapcsolódó issue-k: #32, #82

## Futás adatai

- Dátum:
- Környezet:
- Alkalmazás commit SHA:
- Adatbázis migráció HEAD:
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
- Production blocker:

## Teszteredmények

| Teszteset | Státusz | Megjegyzés | GitHub issue |
| --- | --- | --- | --- |
| UAT-AUTH-01 | NEM FUTOTT | | |
| UAT-AUTH-02 | NEM FUTOTT | | |
| UAT-AUTH-03 | NEM FUTOTT | | |
| UAT-AUTH-04 | NEM FUTOTT | | |
| UAT-AUTH-05 | NEM FUTOTT | | |
| UAT-ONBOARD-01 | NEM FUTOTT | | |
| UAT-ONBOARD-02 | NEM FUTOTT | | |
| UAT-ONBOARD-03 | NEM FUTOTT | | |
| UAT-IMPORT-01 | NEM FUTOTT | | |
| UAT-IMPORT-02 | NEM FUTOTT | | |
| UAT-CAL-01 | NEM FUTOTT | | |
| UAT-CAL-02 | NEM FUTOTT | | |
| UAT-CAL-03 | NEM FUTOTT | | |
| UAT-CAL-04 | NEM FUTOTT | | |
| UAT-COLOR-01 | NEM FUTOTT | | |
| UAT-BOOK-01 | NEM FUTOTT | | |
| UAT-BOOK-02 | NEM FUTOTT | | |
| UAT-BOOK-03 | NEM FUTOTT | | |
| UAT-BOOK-04 | NEM FUTOTT | | |
| UAT-BOOK-05 | NEM FUTOTT | | |
| UAT-BOOK-06 | NEM FUTOTT | | |
| UAT-BOOK-07 | NEM FUTOTT | | |
| UAT-BOOK-08 | NEM FUTOTT | | |
| UAT-BOOK-09 | NEM FUTOTT | | |
| UAT-BOOK-10 | NEM FUTOTT | automatizált konkurenciabizonyíték kötelező | |
| UAT-BOOK-11 | NEM FUTOTT | | |
| UAT-BOOK-12 | NEM FUTOTT | sikeres/sikertelen UI feedback; e-mail nem követelmény | |
| UAT-BOOK-13 | NEM FUTOTT | booking title | |
| UAT-TRAIN-01 | NEM FUTOTT | | |
| UAT-TRAIN-02 | NEM FUTOTT | | |
| UAT-TRAIN-03 | NEM FUTOTT | | |
| UAT-TRAIN-04 | NEM FUTOTT | | |
| UAT-TRAIN-05 | NEM FUTOTT | default 5000 + admin override | |
| UAT-TRAIN-06 | NEM FUTOTT | automatizált atomi rollback bizonyíték | |
| UAT-EDIT-01 | NEM FUTOTT | | |
| UAT-EDIT-02 | NEM FUTOTT | | |
| UAT-EDIT-03 | NEM FUTOTT | | |
| UAT-EDIT-04 | NEM FUTOTT | | |
| UAT-EDIT-05 | NEM FUTOTT | | |
| UAT-EDIT-06 | NEM FUTOTT | duplikálás | |
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
| UAT-REC-09 | NEM FUTOTT | automatizált DST bizonyíték + célzott UAT | |
| UAT-REC-10 | NEM FUTOTT | három scope | |
| UAT-ADMIN-01 | NEM FUTOTT | | |
| UAT-ADMIN-02 | NEM FUTOTT | | |
| UAT-ADMIN-03 | NEM FUTOTT | | |
| UAT-ADMIN-04 | NEM FUTOTT | | |
| UAT-ADMIN-05 | NEM FUTOTT | | |
| UAT-ADMIN-06 | NEM FUTOTT | room group can_book | |
| UAT-ADMIN-07 | NEM FUTOTT | can_repeat csak közvetlen jog | |
| UAT-ADMIN-08 | NEM FUTOTT | globális privacy | |
| UAT-ADMIN-09 | NEM FUTOTT | utolsó admin védelem | |
| UAT-PRICING-01 | NEM FUTOTT | tiered 20 óra = 38 000 Ft | |
| UAT-PRICING-02 | NEM FUTOTT | progressive 20 óra = 50 000 Ft | |
| UAT-PRICING-03 | NEM FUTOTT | Free = 0 | |
| UAT-PRICING-04 | NEM FUTOTT | effective month | |
| UAT-PRICING-05 | BLOKKOLT | Fix óradíj admin RPC/UI production gap | #82 |
| UAT-PRICING-06 | BLOKKOLT | Fix/Free/Tréningterem precedencia teljes E2E az RPC/UI után | #82 |
| UAT-MONTH-01 | NEM FUTOTT | | |
| UAT-MONTH-02 | NEM FUTOTT | | |
| UAT-MONTH-03 | NEM FUTOTT | | |
| UAT-MONTH-04 | NEM FUTOTT | | |
| UAT-MONTH-05 | NEM FUTOTT | Foglalás címe | |
| UAT-CSV-01 | NEM FUTOTT | | |
| UAT-CSV-02 | NEM FUTOTT | automatizált formula-injection bizonyíték | |
| UAT-CSV-03 | NEM FUTOTT | részletes CSV Foglalás címe | |
| UAT-SETTLE-01 | NEM FUTOTT | | |
| UAT-SETTLE-02 | NEM FUTOTT | automatikus immutabilitás bizonyíték | |
| UAT-PAY-01 | NEM FUTOTT | parkoltatott payment UI / redirect | |
| UAT-UX-01 | NEM FUTOTT | | |
| UAT-UX-02 | NEM FUTOTT | | |
| UAT-UX-03 | NEM FUTOTT | | |
| UAT-UX-04 | NEM FUTOTT | | |
| UAT-UX-05 | NEM FUTOTT | folyamatos mobil scroll 07–22 | |
| UAT-PROD-01 | BLOKKOLT | production backup implementáció után | |
| UAT-PROD-02 | BLOKKOLT | restore-drill backup után | |
| UAT-PROD-03 | BLOKKOLT | monitoring megoldás kiválasztása/implementáció után | |

## Lezárt scope-döntések

| Téma | Döntés | Forrás |
| --- | --- | --- |
| Fix user óradíj | MEGTARTVA, production admin UI/RPC szükséges | `DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md` |
| Régi FS v1.0 | TÖRTÉNETI / SUPERSEDED | ugyanott |
| Booking confirmation e-mail | NEM go-live blocker, későbbi fejlesztés | ugyanott |
| Payment backend/UI | backend parkoltatott; aktív UI nincs | ugyanott |
| Heti nézet | nem része a jelenlegi kötelező baseline-nak | `CURRENT_FUNCTIONAL_BASELINE.md` |

## Aktuális production blockerek

- [ ] Fix óradíj biztonságos admin RPC/UI + regressziós teszt + UAT.
- [ ] Production backup automatizálás és off-site példány.
- [ ] Sikeres restore-drill.
- [ ] Production monitoring/heartbeat és alert drill.
- [ ] Teljes manuális UAT a baseline v1.1 ellen.
- [ ] Kritikus független review végleges lezárása.

## Elfogadási döntés

- [ ] Funkcionálisan és production readiness szempontból GO.
- [ ] Funkcionális baseline rendben, de production blocker(ek) még nyitottak.
- [ ] P1/P2 funkcionális javítás szükséges.

Indoklás / megjegyzés:
