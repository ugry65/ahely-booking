> **Friss ellenőrzés – 2026-09-21, PR #175 után:** main `930fd6a39056e1d652b1d055d506a2956ea3fdce`. A merge utáni három CI workflow PASS, négy legfrissebb Vercel deployment READY és ugyanezt a SHA-t mutatja. Az e-mail migrációk stagingen alkalmazva vannak; productionben egyik sem. A runtime mód és titkok élő értéke nem igazolt. Az alábbi 2026-09-18-i ág- és teendőlista **történeti pillanatkép**, nem a mai main állapota. A jelenlegi e-mail élesítési terv: [BOOKING_EMAIL_PRODUCTION_READINESS.md](BOOKING_EMAIL_PRODUCTION_READINESS.md). Ez nem production send engedély.\n\n# Kiadási bizonyítékok és ágak egyeztetése

Ellenőrzés: 2026-09-18. Az alábbi leltár történeti baseline. A történeti dokumentumok dátumozott állításait az akkori környezetre kell értelmezni.

## Rögzített forrásverziók

- main: `bfb1f346c8b93c6e1f6184ac5892591cec3b9889` (PR #172).
- staging: `c71f790e20e979898ac38f934ddb243747d008bc`.
- Teljes rekurzív Git fájllista alapján **259 eltérő fájl**. A tételes, blob SHA-val rögzített leltár: [branch-inventory.json](branch-inventory.json). Ez két fájfa összehasonlítása, nem a merge-base-hez képesti PR diff.
- A main és a staging eltérő fejlesztéseket tartalmaz. A staging egészének átmásolása felülírhatná a main újabb javításait.

## Bizonyíték és kiadási állapot

| Terület | Bizonyíték | main / éles állapot határa |
| --- | --- | --- |
| Korábbi funkcionális UAT | Augusztus 30-i egyeztetés: 50 PASS, 22 modul-elfogadás, 1 döntéssel lezárt, 22 bizonyíték-egyeztetendő, 3 akkori production blokk; nincs dokumentált FAIL. | Történeti staging eredmény, nem 22 új teszt és nem jelenlegi production GO. |
| Foglalás / módosítás / lemondás / ismétlődés | Imre 2026-09-18-i közlése: valamennyi kipróbált lépés működött, értesítést kapott. Korábbi tételes jegyzőkönyv is rendelkezésre áll. | Felhasználói megerősítés; ebből új pontos futási időpontot, SHA-t vagy teszteset-számot nem képzünk. |
| Booking e-mail capture | 16/16 captured; create/update/cancel, admin owner címzés, series/occurrence/following; üres sor ismételt feldolgozása no-op. | Capture nem valódi kézbesítés. A megvalósítás stagingen megvan, mainben hiányzik. |
| Valós Resend kézbesítés | Szeptember 10-i jegyzőkönyv: create/update/cancel PASS, megfelelő címzett és tartalom. | A jegyzőkönyv még nyitottnak jelöl további eseteket; a későbbi felhasználói elfogadást külön forrásként kezeljük. Production aktiválás nincs ezzel bizonyítva. |
| Admin más nevében | Elfogadott követelmény; staging capture tesztben az értesítés a booking ownerhez tartozik. | Nem új üzleti döntés és nem újra megvalósítandó funkció. |
| Backup és monitoring | A beszélgetésben ütemezett sikeres backupok, restore-drill eredmények és DOWN/UP riasztás bizonyítékai szerepelnek. | Nem minősítjük újra hiányzónak egy régi dokumentum alapján. Az aktuális szolgáltatói állapotot ez a Git-audit nem kérdezte le. |
| Együgyfeles import, health végpont, backup workflow | main kódban megvannak; a gépi nyilvántartás kulcsfájlokat rögzít. | A kódfájl megléte nem deployment-, secret- vagy működési bizonyíték. |

## Változatlanul megőrzött történeti források

Az alábbi fájlok a fenti staging commit pontos másolatai. A gépi ellenőrzés Git blob SHA-val védi őket. Nem írjuk át bennük a régi nyitott állapotokat utólagos sikerre.

- [UAT_FUTASI_JEGYZOKONYV.md](evidence/2026-09-18-staging/UAT_FUTASI_JEGYZOKONYV.md) — [eredeti verzió](https://github.com/ugry65/ahely-booking/blob/c71f790e20e979898ac38f934ddb243747d008bc/docs/UAT_FUTASI_JEGYZOKONYV.md).
- [FUNKCIONALIS_UAT_CHECKLIST.md](evidence/2026-09-18-staging/FUNKCIONALIS_UAT_CHECKLIST.md) — [eredeti verzió](https://github.com/ugry65/ahely-booking/blob/c71f790e20e979898ac38f934ddb243747d008bc/docs/FUNKCIONALIS_UAT_CHECKLIST.md).
- [BOOKING_EMAIL_RESEND_STAGING_UAT.md](evidence/2026-09-18-staging/BOOKING_EMAIL_RESEND_STAGING_UAT.md) — [eredeti verzió](https://github.com/ugry65/ahely-booking/blob/c71f790e20e979898ac38f934ddb243747d008bc/docs/BOOKING_EMAIL_RESEND_STAGING_UAT.md).
- [UAT_CHECKPOINT_2026-08-30.md](evidence/2026-09-18-staging/UAT_CHECKPOINT_2026-08-30.md) — [eredeti verzió](https://github.com/ugry65/ahely-booking/blob/c71f790e20e979898ac38f934ddb243747d008bc/docs/UAT_CHECKPOINT_2026-08-30.md).

Kapcsolódó PR-ok: [#111](https://github.com/ugry65/ahely-booking/pull/111) booking outbox (az ellenőrzéskor nyitott, célága fix/109-mobile-responsive-pages); [#147](https://github.com/ugry65/ahely-booking/pull/147) Resend; [#148](https://github.com/ugry65/ahely-booking/pull/148) worker időzítés (utóbbi kettő stagingbe merge-elve).

## Mi okozta a téves státuszt?

A main-only vizsgálat összekeverte a „mainből hiányzik” és a „nem készült el / nem tesztelt” állapotokat. A mainen megmaradt régi, üres UAT-sablon és a stagingen lévő elfogadások eltérése nem volt egyeztetve. A PR #171/#172 dokumentációja ezért nem teljes kiadási audit.

## Kötelező eljárás minden további átadásnál

1. Rögzítsd a main, staging és kiadási jelölt pontos SHA-ját; ne használj dátum nélküli „minden kész” állítást.
2. Ellenőrizd a kapcsolódó PR-ok célágát, merge-állapotát és a kiadási jelölt tényleges fájljait.
3. Külön kezeld: követelmény, implementált ág, történeti elfogadás, új regressziós ellenőrzés, telepített SHA, élő környezeti ellenőrzés.
4. A felhasználó korábbi elfogadása nem írható NEM FUTOTT-ra hiányzó kattintási napló miatt. Újrateszteléshez konkrét módosítás vagy reprodukált hiba és célzott scope kell.
5. Staging → main integrációnál háromutas egyeztetés kell; megőrzendők a main naptár-, számlázási cím-, health-, import- és backup-javításai. Függőségek, migration-sorrend, scheduler és futtatókörnyezet külön ellenőrzendő.
6. A végleges jelölthöz tartozó CI-t és szükséges független review-t rögzítsd. Régi zöld futás nem az új kód teszteredménye.
7. Merge után ellenőrizd a tényleges deployment SHA-t és a szükséges DB-migrációk állapotát. A kiadási elfogadáshoz valós production bizonyíték szükséges.
8. main merge és production konfiguráció/DB/e-mail-aktiválás csak az arra vonatkozó jóváhagyással történhet.

## Automatikus védelem és korlátai

- `node scripts/check-release-evidence.mjs`: ellenőrzi a történeti másolatok SHA-ját és a nyilvántartott kódfájlok állapotát. Elavult állapot vagy részleges e-mail-integráció hibát ad.
- `node --test scripts/test-release-evidence.mjs`: pozitív és negatív regressziós esetek.
- `node scripts/check-release-evidence.mjs --release`: az előzőeken túl megköveteli a kiadáshoz szükséges funkciók jelenlétét és a nyitott kiadási blokkok lezárását. **Jelenleg szándékosan hibával áll meg.**
- A `Release evidence` workflow minden PR-on és main/staging pushon lefuttatja a konzisztenciaellenőrzést. Ez nem automatikus élesítési engedély.
- A GitHub branch protection required-check beállítása ebben a változtatásban nem módosult. A release ellenőrzés nem épül be automatikusan a meglévő deployment workflow-kba; az integrációs release kötelező ellenőrzési lépése.
- A fájl- és hash-ellenőrzés nem bizonyít szemantikai helyességet, levélkézbesítést vagy szolgáltatói konfigurációt. A nyilvántartás módosítása review-köteles.

## Hátralévő konkrét munka

1. A 259 fájlos eltérésből az elfogadott funkciók és szükséges függőségeik integrációs PR-ja, a frissebb main-javítások megőrzésével.
2. Az integrált kód automatikus ellenőrzése és kritikus részeinek független review-ja.
3. A production deployment, DB-migrációk és e-mail konfiguráció egyezésének ellenőrzése; szükséges változtatások jóváhagyása, majd célzott ellenőrzés.
4. Többügyfeles import továbbra is külön fejlesztés; a jelenlegi együgyfeles import korlátja nem változott.

Ez a rendezés nem integrálja az e-mail kódot és nem jelent teljes élesítési GO-t.
