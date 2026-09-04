# A-Hely foglalási rendszer – Teljes funkcionális és újraimplementálási baseline

Verzió: 1.2
Dátum: 2026-08-26
Elfogadási státusz és dokumentációs helyesbítés: 2026-08-30; az ismétlési jog leírása a már elfogadott PR #77 / 2026-08-22 döntéshez igazítva, új üzleti szabály nélkül. Bizonyíték: [tételes egyeztetés](UAT_BIZONYITEK_EGYEZTETES_2026-08-30.md).
Állapot: **kanonikus funkcionális és újraimplementálási specifikáció; staging baseline, a külön production-readiness kapukkal**

## 0. A dokumentum célja és használata

Ez a dokumentum nem fejlesztési ötletlista és nem csupán UAT-checklist. A célja, hogy az A-Hely foglalási rendszer jelenlegi, stagingen elfogadott működését és a már véglegesen elfogadott production-követelményeket technológiától és konkrét forráskódtól függetlenül olyan részletességgel rögzítse, hogy a rendszer szükség esetén **nulláról újraimplementálható legyen más forráskóddal, más frameworkkel vagy más szolgáltatói infrastruktúrán**, miközben az üzleti működés, jogosultságok, adatbiztonsági invariánsok és felhasználói élmény megmaradnak.

Ha ez a dokumentum és egy régebbi beszélgetés eltér, ez a dokumentum és az aktuális projektkontextus az irányadó, kivéve új, explicit, későbbi üzleti döntést.

### Forrásprioritás

1. `docs/CURRENT_FUNCTIONAL_BASELINE.md` – **elsődleges, kanonikus as-built/újraimplementálási specifikáció**;
2. `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md` és az ott hivatkozott aktuális döntési dokumentumok;
3. a részletes UI/UX, admin, riport, pricing, sorozat-scope és production-readiness dokumentumok;
4. az `A-Hely_Foglalasi_Rendszer_Funkcionalis_Specifikacio_v1.0.docx` kizárólag **TÖRTÉNETI / SUPERSEDED** forrás. Nem használható önálló vagy elsődleges implementációs specifikációként, mert több pontját későbbi explicit üzleti döntések felülírták.

Kapcsolódó kötelező források:
- `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`;
- `docs/BOOKING_UI_UX_BASELINE.md`;
- `docs/FUNKCIONALIS_UAT_CHECKLIST.md`;
- `docs/ADMIN_USER_MANAGEMENT.md`;
- `docs/ADMIN_REPORTING_RULES.md`;
- `docs/PRICING_MODES.md`;
- `docs/SERIES_SCOPE_SEMANTICS.md`;
- `docs/DECISION_2026-08-25_FINANCIAL_SCOPE_AND_TRAINING_GROUP_RATE.md`;
- `docs/DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md`;
- `docs/CLAUDE_BASELINE_REVIEW_RESOLUTION_2026-08-26.md`;
- `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md`;
- `docs/PRODUCTION_READINESS_CHECKLIST.md`.

A konkrét jelenlegi technológia Next.js/React + Supabase/PostgreSQL, de az alábbi követelmények **nem függhetnek ettől a technológiától**.

---

# 1. Rendszercél és hatókör

Az alkalmazás az A-Hely saját belső helyiségfoglaló rendszere, a Skedda/AllBooked napi foglalási működésének kiváltására. Nem általános SaaS termék.

A rendszer fő feladatai:
1. felhasználók hitelesítése és kezelése;
2. helyiségek és foglalási jogosultságok kezelése;
3. napi többhelyiséges foglalási naptár;
4. egyszeri és ismétlődő foglalások;
5. foglalások módosítása, duplikálása és lemondása;
6. dupla foglalás adatbázis-szintű megakadályozása;
7. Tréningterem speciális működés;
8. havi órák és fizetendő összeg számítása;
9. userenkénti **Sávos / Progresszív / Fix óradíj / Free** díjazás, időbeli érvényességgel;
10. admin riportok és exportok;
11. auditálhatóság és történeti konzisztencia.

Nem része az aktuális aktív scope-nak:
- bankkártyás fizetés;
- befizetések kézi könyvelésének UI-ja;
- közvetlen számlázó-integráció;
- komplex pénzügyi dashboard;
- natív mobilapp;
- SSO/SAML;
- általános SaaS/membership funkciók.

---

# 2. Nyelv, időzóna, pénznem és alapidő-szabályok

- UI nyelve: magyar.
- üzleti időzóna: `Europe/Budapest`;
- pénznem: HUF;
- napi nyitvatartás/foglalható idősáv: 07:00–22:00;
- időrács: 30 perc;
- minimum foglalási idő: 60 perc;
- 60, 90, 120 stb. perces foglalás engedélyezett;
- aktív normál user és admin múltbeli időpontra is létrehozhat egyszeri vagy ismétlődő foglalást; a többi jogosultsági, időrács-, nyitvatartási és ütközési szabály változatlan;
- nincs globális hétvégi/zárt-nap tiltás: bármely naptári nap használható a többi szabály keretein belül;
- időintervallumok félig nyitottként kezelendők: `[start, end)`, ezért 10:00–11:00 és 11:00–12:00 nem ütközik;
- minden hónap- és dátumhatár Europe/Budapest szerint számítandó, DST-t is helyesen kezelve.

---

# 3. Szerepkörök és biztonsági modell

## 3.1 Szerepkörök

Két alkalmazásszerepkör:
- `admin` / Adminisztrátor;
- `user` / Normál felhasználó.

A jogosultságot backend/adatbázis oldalon is ellenőrizni kell. UI-elemek elrejtése önmagában nem jogosultságvédelem.

## 3.2 Aktív/inaktív állapot

A user aktív vagy inaktív. Inaktív user védett funkciót nem használhat közvetlen URL-lel vagy manipulált API-kéréssel sem.

## 3.3 Utolsó admin védelme

Az utolsó aktív adminisztrátort nem lehet:
- normál userré lefokozni;
- deaktiválni.

Ezt backend/DB szinten kell kikényszeríteni.

## 3.4 Admin más user nevében

Admin foglalhat más aktív user nevében. A foglalás tulajdonosa a kiválasztott user; az auditban az actor a műveletet végrehajtó admin. Normál user más `user_id` értékét kliensmanipulációval sem adhatja meg.

A pénzügyi elszámolás mindig a **foglalás tulajdonosának** pricing policy-ját használja, nem a foglalást végrehajtó adminét.

---

# 4. Felhasználói életciklus

## 4.1 Admin által létrehozott user

Minimum admin által megadandó:
- vezetéknév;
- keresztnév;
- e-mail.

Létrehozáskor nincs automatikus aktiváló levél. Az admin külön indítja az `Aktiváló / jelszóbeállító link küldése` műveletet.

## 4.2 Aktiválás és jelszó

Onboarding előtt a művelet aktiváló/jelszóbeállító link; onboarding után jelszó-visszaállító link. Csak aktív admin indíthatja aktív usernek. Token, jelszó és reset URL nem kerülhet alkalmazás-audit payloadba.

## 4.3 Első belépési onboarding

Normál user első jelszóbeállítás után nem használhatja a foglalási rendszert, amíg nem tölti ki:
- telefonszám;
- számla típusa: magánszemély/vállalkozó;
- számlázási név;
- irányítószám;
- település;
- utca;
- házszám;
- vállalkozónál adószám kötelező.

Lehetőség: `A számlázási név megegyezik a nevemmel` → vezetéknév + keresztnév automatikus átvétele.

Sikeres befejezés időpontja tárolandó (`onboarding_completed_at` jellegű adat), a művelet auditált. Adminra onboarding blokkolás nem vonatkozik.

## 4.4 CSV user import

Kötelező oszlopok:
`last_name, first_name, email`

Szabályok:
- csak admin;
- fájlon belüli duplikált e-mail hiba;
- már létező e-mail kihagyható;
- új auth/user rekord készül automatikus aktiváló levél nélkül;
- ideiglenes jelszó nem tárolható/megjeleníthető;
- számlázási adatokat a user tölti ki onboardingkor.

---

# 5. Helyiségek és hozzáférési csoportok

Kanonikus induló helyiségek:
- Tréningterem;
- 1.Szoba-családi;
- 2.Szoba;
- 3.Szoba;
- 4.Szoba;
- 5.Szoba;
- 6.Szoba;
- Gyerek szoba;
- Pitypang szoba;
- Csoport szoba;
- Forrás tér.

Kanonikus csoportok:
- `A-Hely`: Gyerek szoba, Pitypang szoba, Csoport szoba;
- `Másik Hely`: 1.Szoba-családi, 2.Szoba, 3.Szoba, 4.Szoba, 5.Szoba, 6.Szoba;
- `Tréningterem`: Tréningterem;
- `Forrás tér`: Forrás tér.

Egy user több csoport tagja lehet.

Effektív foglalási jog:
`közvetlen user–szoba can_book + aktív csoportból származó can_book`.

Fontos invariáns: csoport **csak can_book** jogot ad. Az ismétlési jog **felhasználó-szintű**: normál usernél `profiles.can_repeat_bookings=true` + az adott helyiségre effektív `can_book` + nem Tréningterem. A foglalási jog csoportból vagy közvetlen kivételből is származhat. Kikapcsolt profil-repeat mellett nincs ismétlés; admin Tréningteremben is ismételhet.

A `user_room_permissions.can_repeat` történeti kompatibilitási mező, nem önálló helyiségszintű jogforrás. A támogatott legacy admin RPC TRUE jelzése auditáltan bekapcsolhatja a profil-repeat jogot; közvetlen kliens-táblaírás nem támogatott. A teljes szabály és a kikapcsolás/lock-sorrend: [RECURRING_PERMISSION_RULES](RECURRING_PERMISSION_RULES.md), [elfogadott 2026-08-22 döntés](ACCESS_AND_REPEAT_DECISIONS_2026-08-22.md). A korábbi „kizárólag közvetlen user–szoba jog” mondat dokumentációs hiba volt.

A meglévő közvetlen jogokat csoporttagság nem törölheti/felülírhatja.

---

# 6. Naptár – desktop és mobil baseline

## 6.1 Általános napi nézet

Alapértelmezett főoldal: napi, többhelyiséges naptár.
- helyiségek oszlopokban;
- 07:00–22:00;
- foglalási blokkok időarányosan;
- saját foglalás vizuálisan elkülönül;
- egész órás vonal hangsúlyosabb, félórás finomabb;
- az időoszlop és helyiségoszlopok rácsa ugyanabból a percalapú geometriából számítandó.

Desktop cél: tömör, Skedda-szerű áttekintés, lehetőség szerint a teljes napi sáv egy képernyőn.

## 6.2 Mobil

- kompakt A-Hely fejléc + hamburger;
- hamburger menü route-váltáskor bezár;
- felső 7 napos sáv: kiválasztott nap + következő 6;
- kiválasztott nap kör alakú kiemelés;
- külön naptárikon → havi dátumválasztó;
- sticky bal órasáv vízszintes scrollnál;
- teljes naptárfelületen természetes függőleges scroll;
- mobil foglaláskijelölés csak long press után;
- long press előtt meginduló scroll megszakítja a foglalási szándékot;
- iOS/Safari natív text selection/touch callout tiltandó a naptárgesztuson;
- kijelölés után ujjfelengedéskor azonnal megnyílik a foglalási modal;
- nincs köztes mobil `Foglalás` gomb.

## 6.3 Foglalás indítása

Két kötelező mód:
1. naptári kijelölés;
2. jobb alsó fix `+` gyorsfoglalás.

Mindkettő mobilon és desktopon megmarad.

---

# 7. Foglalási modal és adatok

Foglalásnál kezelendő:
- tulajdonos user;
- helyiség;
- dátum;
- kezdés;
- befejezés;
- használattípus;
- megjegyzés;
- foglalás címe (`booking_title` jellegű adat);
- egyszeri/ismétlődő beállítások;
- Tréningterem csoportos admin foglalásnál egyedi óradíj.

Naptárból indításkor helyiség/dátum/idő előtöltődik, de modalban módosítható.

Normál helyiségnél használat automatikusan `Egyéni`; Egyéni/Csoportos választó csak Tréningteremnél jelenhet meg.

Mentés nélküli bezárás (X, Mégse, backdrop) nem hagyhat fantom `Új foglalás` blokkot.

## 7.1 Foglalási siker-visszajelzés és e-mail

A 2026-09-02-i üzleti döntés felülírja a korábbi opcionális e-mail állapotot. Minden sikeres create/update/cancel foglalási művelet után a foglalás tulajdonosa kötelező e-mailt kap, admin által végzett műveletnél is. Sorozatos vagy `following`/`series` scope művelethez egy összefoglaló e-mail tartozik.

A foglalási tranzakció és az értesítési kötelezettség transactional outboxban együtt rögzül. Külső e-mail-szolgáltatói hiba a foglalást nem gördítheti vissza; az értesítés retryzható és auditálható marad. Részletes technikai döntés: `docs/DECISION_2026-09-03_BOOKING_EMAIL_OUTBOX.md`.

A #111 draft ágon a kanonikus create/update/cancel és sorozatos/scope RPC-k korrelált auditjából egy tranzakció végéig halasztott, belső trigger készít pontosan egy változtathatatlan outbox rekordot. Ez a title- és admin díjazási mellékhatások lezárása után, de még ugyanabban a booking tranzakcióban fut. A GitHub Database tests #525 friss resetből 714/714 pgTAP, minden konkurenciateszt és schema lint PASS eredményt adott; staging alkalmazás és valós e-mail-küldés még nem történt.

Ugyanezen a draft ágon elkészült a szigorú `payload_version=1` alkalmazásoldali validáció, a magyar text/HTML create/update/cancel és sorozat-összefoglaló renderer, az adminjelzés, HTML/header-injection védelem, `Europe/Budapest` DST-formázás, valamint a providerfüggetlen transport adapter.

A verzióra rögzített Nodemailer SMTP-kliens és a belső Node.js worker Route Handler is bekötésre került. A végpont legalább 32 bájtos `CRON_SECRET` Bearer tokent követel, a service-role kulcs és az SMTP-titkok kizárólag szerveroldali változók. A `BOOKING_EMAIL_MODE` alapértéke `disabled`, ekkor a worker nem claimel; a `capture` és `send` mód csak explicit konfigurációval aktív. A worker kis batchben claimel, payloadot és scope-ot validál, majd sent/captured/retry/dead-letter eredményt rögzít biztonságos hibával. A helyi teljes csomag 22 fájl / 125 teszt, typecheck, build és dependency audit PASS; a végleges kódcommiton Application checks #581, Database tests #530 és Vercel PASS. Valós SMTP-küldés vagy staging DB-módosítás nem történt.

A #111 draft ágon elkészült az append-only worker-futásaudit és az admin-only `/admin/email-ertesitesek` kézbesítési monitor is. A worker `capture`/`send` futása start/finish heartbeatot és titokmentes összesítést rögzít; a `disabled` mód továbbra sem érinti az adatbázist. A monitor kizárólag minimalizált állapotot mutat: darabszámokat, esedékességet, stale lease/futást, utolsó küldést és heartbeatot, biztonságos hibát, valamint belső auditazonosítót. Címzett, e-mail cím, booking payload, levéltartalom, provider Message-ID és secret nem kerül a read modelbe. Kézi retry nincs. A commit `1660e61` helyben 23 tesztfájl / 134 teszt, typecheck és build PASS; GitHub Application checks #583, Database tests #532 (52 fájl / 749 pgTAP, minden konkurenciateszt és schema lint) és Vercel PASS. Staging DB-alkalmazás vagy valós küldés továbbra sem történt.

A 2026-09-04-i automatikus staging deploy #14 sikeresen alkalmazta a `20260830183000` cutoff-guard és a `202609030001`, `202609030002`, `20260903185410` booking-email migrációkat. A local/remote history egyezik, a deploy utáni dry-run és a megismételt no-op deploy #15 szerint a remote adatbázis naprakész. Közvetlen read-only ellenőrzés igazolta, hogy az outbox, delivery-attempt és worker-run táblák léteznek, mindhárom üres, az `authenticated` szerepkörnek nincs közvetlen tábla-hozzáférése, a szükséges service-role worker execute jogok pedig jelen vannak. E-mailt ez a lépés nem küldött. A scheduler, runtime secret, capture UAT és valós SMTP UAT továbbra is nyitott; ez nem production GO.

A 2026-09-04-i staging infrastruktúra-döntés szerint a jóváhagyott pontos commit dedikált `staging` branchre történő, force nélküli promóciója automatikus dry-run → staging DB deploy → nulla függő migráció utóellenőrzést indít. Előfeltétel a zöld Application CI és Database CI, az elvárt dry-run és a projektgazda kifejezett staging-jóváhagyása. A staging secret csak a GitHub `staging` Environmentben használható; PR nem kap remote adatbázis-hozzáférést. Ez nem main merge és nem production deploy. Részletes döntés: `docs/DECISION_2026-09-04_STAGING_PROMOTION_AUTOMATION.md`.

A staging Preview branch-scope runtime konfigurációja 2026-09-04-én elkészült `capture` módban, SMTP-változók nélkül. A cache nélküli redeploy `READY`, a build és TypeScript ellenőrzés PASS. Az első egyedi create/update/cancel UAT pontosan egy-egy új `booking.created`, `booking.updated`, `booking.cancelled` rekordot adott ugyanahhoz a tesztfoglaláshoz; egy további create kontrollrekorddal összesen négy `pending` értesítés vár feldolgozásra. Valós e-mail nem ment ki. A teszt előtti 135 legacy outbox rekord változatlan, az UAT booking műveletei külön négy új kanonikus legacy audit-eseményt hoztak létre. A titok kézi visszaolvasása helyett a staging admin e-mail monitor capture-only indítást kap: minden futás újra ellenőrzi az aktív admin jogosultságot és a `capture` módot, `send` vagy `disabled` esetén fail-closed módon megtagadja az indítást.

Továbbra is kötelező:
- sikeres mentés után a UI egyértelműen jelezze a sikert;
- a foglalás azonnal jelenjen meg a naptárban és a releváns saját-foglalási nézetben;
- sikertelen vagy visszagördített foglalás nem jelenhet meg sikeresként;
- technikai hiba esetén érthető hibaüzenet jelenjen meg, félkész foglalás nélkül.

Az e-mail funkció production gate: stagingen valós create/update/cancel, adminművelet, sorozat-összefoglalás, retry és kézbesítési napló UAT szükséges.

---

# 8. Egyedi foglalás üzleti szabályai

Sikeres foglaláshoz egyszerre teljesüljön:
- aktív és jogosult user;
- foglalható helyiség;
- megfelelő can_book jog;
- múltbeli, mai vagy jövőbeli dátum; jövőbeli dátumnál az előrefoglalási limit is teljesüljön;
- 07:00–22:00;
- 30 perces rács;
- minimum 60 perc;
- előrefoglalási limit;
- nincs aktív átfedő foglalás.

A backendnek kliensmanipuláció esetén is el kell utasítania a szabálytalan foglalást.

## 8.1 Dupla foglalás elleni védelem

Kötelező adatbázis-szintű kizárás/konkurenciavédelem. Két egyidejű, azonos helyiségre és átfedő időre érkező kérésből legfeljebb egy lehet sikeres.

## 8.2 Idempotencia

Azonos idempotenciakulccsal megismételt létrehozási kérés nem hozhat létre második foglalást.

---

# 9. Előrefoglalási limitek

Normál helyiségek default előrefoglalási limitje központi paraméter, alapértéke 90 nap, userenként felülírható.

Tréningterem normál user default limitje 10 nap, admin által állítható.

Adminra az üzleti adminjogok szerinti eltérő kezelés alkalmazható, de normál user nem kerülheti meg a limitet.

---

# 10. Tréningterem speciális működés

## 10.1 Használattípus

Tréningterem lehet:
- Egyéni;
- Csoportos.

Normál szobáknál nincs Csoportos opció.

## 10.2 Ismétlődés

Normál user Tréningteremre ismétlődő sorozatot nem hozhat létre. Admin igen.

## 10.3 Csoportos díj

Default csoportos díj: **5000 Ft/óra**.

Admin foglalásonként más óradíjat adhat meg (például nagyobb létszám esetén). Az egyedi díj a konkrét foglaláshoz tartozik és történetileg megőrzendő.

A foglalás/sorozat létrehozása és az admin egyedi díj rögzítése **egy tranzakció**: vagy minden sikerül, vagy semmi. Nem maradhat 5000 Ft-os félkész foglalás azért, mert az egyedi díj rögzítése hibázott.

Free user esetén a Tréningterem csoportos díja is 0 Ft.

## 10.4 Foglalás címe

Tréningterem admin foglalásnál a cím üzletileg fontos, mert ebből látszik, kinek/milyen csoportnak történt a foglalás. A cím megőrzendő és a havi tételes riportban/exportban visszaadandó.

---

# 11. Ismétlődő foglalások

Támogatott gyakoriság:
- napi;
- heti;
- kétheti;
- havi.

Sorozat végződhet:
- darabszámmal;
- végdátummal.

Kivételdátumok támogatottak.

A helyi kezdési időt DST-váltás mellett is meg kell őrizni.

Ütközés esetén két üzleti mód:
1. teljes sorozat megszakítása / semmi nem jön létre;
2. csak a szabad alkalmak létrehozása, az ütközők kihagyása.

Sorozat létrehozása ugyanabból a foglalási modalból indul, nem külön főoldali workflowból.

## 11.1 Sorozat-scope definíció

A három user-facing scope pontos, kötelező jelentése:
- **Aktuális alkalom (`occurrence`)**: csak a kiválasztott konkrét aktív jövőbeli booking;
- **Ettől kezdve (`following`)**: a kiválasztott booking és minden, ugyanazon sorozathoz tartozó, nála később kezdődő aktív jövőbeli booking;
- **Teljes sorozat (`series`)**: a sorozat összes aktív, a művelet időpontjában még jövőbeli bookingja, függetlenül attól, melyik alkalomról indult a művelet.

Már lezajlott vagy korábban cancelled alkalmat egyik sorozat-scope sem ír át visszamenőleg.

## 11.2 Sorozat szerkesztése

A kiválasztott booking új kezdési ideje és eredeti kezdési ideje közötti időeltolás minden érintett booking saját eredeti kezdésére azonosan alkalmazandó. Az új kezdés/befejezés különbsége adja az új, minden érintett bookingra alkalmazott durationt. Ugyanígy minden target az új helyiséget, használattípust és megjegyzést kapja.

A rendszer az összes target célállapotát előre validálja. Ha egyetlen célbooking jogosulatlan, időszabályt sért vagy ütközik, a teljes scope-update visszagördül; részleges módosítás nem maradhat.

A kiválasztott booking optimista konkurenciaverzióját ellenőrizni kell; stale állapotból scope-update nem indulhat.

A `booking_title` nem része a tömeges scope-update mezőinek, ezért a már meglévő cím bookingonként megmarad.

## 11.3 Tréningterem díj öröklése scope-update során

A foglalásspecifikus csoportos óradíj nem teríthető szét implicit módon a sorozatra.
- ha egy booking Tréningterem + Csoportos marad, a rajta tárolt saját 5000/7500/stb. csoportdíj megmarad;
- ha már nem Tréningterem + Csoportos, a speciális csoportdíj nullázódik;
- ha korábban nem volt Tréningterem + Csoportos, de a módosítás azzá teszi, és nincs booking-specifikus díj, a default **5000 Ft/óra** lép életbe;
- új egyedi csoportdíj tömeges beállítása csak külön explicit admin díjművelet lehet.

Normál user ismétlődő Tréningterem-sorozatot nem kezelhet sorozatként.

## 11.4 Sorozat lemondása

A `occurrence/following/series` célhalmaz ugyanaz, mint szerkesztésnél. Az érintett bookingok `cancelled` állapotba kerülnek, nem számítódnak el, az idősáv felszabadul, de a booking fizikailag megmarad és cancellation snapshot + audit keletkezik.

Normál usernél a teljes célhalmazt a 24 órás/cancellation cutoff ellen a módosítás előtt ellenőrizni kell. Ha akár egyetlen érintett booking cutoffon belül van, a teljes scope-cancel sikertelen; részleges lemondás nem történhet. Admin a normál user cutoffot megkerülheti.

## 11.5 Történet, idempotencia

A scope-művelet nem új recurrence-generálás. Az eredeti `booking_series`/occurrence generálási adatok auditforrások; az aktuális élő állapotot a bookingok adják. A scope-műveletek actorhoz és idempotenciakulcshoz kötve auditálandók, azonos request ismétlése nem duplikálhatja a hatást.

A teljes rekord-szintű szemantika kötelező részletspecifikációja: `docs/SERIES_SCOPE_SEMANTICS.md`.

---

# 12. Foglalás módosítása és duplikálása

Normál user saját, megfelelő időtávban lévő foglalását módosíthatja. Módosításkor ugyanazokat a jogosultsági, idő-, átfedési és előrefoglalási szabályokat újra ellenőrizni kell.

Normál user 24 órán belül kezdődő foglalását nem módosíthatja a tiltott szabály megkerülésére.

Ütköző/jogosulatlan módosítás esetén az eredeti foglalás változatlan marad.

Párhuzamos módosításnál optimista konkurenciavédelem szükséges: elavult kérés nem írhatja felül az újabb állapotot.

Naptári műveletek között elérhető: Szerkesztés, Duplikálás, Törlés/Lemondás a jogosultság szerint.

---

# 13. Lemondás és törlés

Normál user saját foglalását 24 órán túl lemondhatja; 24 órán belül nem.

Admin bármikor törölhet az admin szabályok szerint.

Törlés/lemondás üzleti értelemben nem fizikai adatvesztés: a történeti rekord/audit megmarad.

A cancelled foglalás:
- nem jelenik meg aktív foglalásként;
- felszabadítja az idősávot;
- nem számít bele havi elszámolandó órába;
- nem növeli a fizetendő összeget.

Sorozat egyetlen alkalma külön is lemondható a többi alkalom törlése nélkül.

Lemondásnál történetileg megőrzendő legalább:
- booking;
- lemondás időpontja;
- lemondó actor;
- indok, ha rendelkezésre áll;
- eredeti kezdés;
- kezdésig hátralévő idő.

---

# 14. Foglaló neve, privacy és stabil naptárszín

Minden userhez stabil `calendar_color` jellegű szín tartozik, nem oldalbetöltésenként random.

40 színes paletta: első 40 user lehetőség szerint külön szín, utána legkevésbé használt szín ismétlődhet.

Más foglalók nevének láthatósága globális admin beállítás.
- bekapcsolva: más user neve és engedélyezett színe megjelenhet;
- kikapcsolva: más user neve **és stabil színe sem adható ki normál usernek**, mert a szín azonosító lehet; semleges `Foglalt` megjelenés;
- saját foglalás mindig felismerhető;
- admin adminisztrációs célból látja a szükséges identitást.

---

# 15. Díjazási modell

Az admin üzleti szinten négy díjazási lehetőség közül választ: **Sávos / Progresszív / Fix óradíj / Free**. A jelenlegi adatmodell ezt technikailag úgy valósítja meg, hogy a `tiered/progressive/free` policy mellett külön `user_price_overrides` réteg tárolja a Fix óradíjat. Egy másik technológiában ez megvalósítható egyetlen négyértékű policy-modellel is, feltéve hogy a lent rögzített precedencia és történeti jelentés változatlan marad.

## 15.1 Elszámolandó foglalás

Csak `active` foglalás számlázódik. Törölt/lemondott foglalás nem.

## 15.2 Default sávos (`tiered`)

Default minden új usernél.

Aktuális sávok:
- 1–15 óra: 2700 Ft/óra;
- 16–60 óra: 1900 Ft/óra;
- 61 órától: 1700 Ft/óra.

A hónap teljes elszámolandó **normál** óraszáma kiválaszt egy sávot, és annak díja az összes normál órára érvényes.

Példa: 20 normál óra → `20 × 1900 = 38 000 Ft`.

## 15.3 Progresszív (`progressive`)

A sávok csak saját tartományukra vonatkoznak.

Példa: 20 óra → `15 × 2700 + 5 × 1900 = 50 000 Ft`.

## 15.4 Fix óradíj (`fixed_user` üzleti mód)

Admin userenként fix normál óradíjat állíthat be, havi érvényességgel. Például 2200 Ft/óra esetén a user adott havi normál órái `óraszám × 2200 Ft` szerint számolódnak, függetlenül attól, hogy a háttér-policy korábban sávos vagy progresszív volt.

A Fix óradíj csak a **normál** órákra vonatkozik. A Tréningterem csoportos használata külön speciális díjszabály szerint számítódik, kivéve Free usert.

A dedikált, auditált admin RPC/UI implementálva van. Az admin a Díjazás felületen kiválaszthatja a Fix módot, megadhatja a Ft/óra értéket és a kezdő hónapot. A kliensoldal kizárólag az egységes pricing-konfigurációs backend műveleten keresztül módosíthat; a belső policy-helper közvetlen authenticated végrehajtása tiltott.

A Fix admin funkció kódoldali hiánya lezárt; staging manuális UAT-ja is elfogadva (UAT-PRICING-05/06, 2026-08-30-i jegyzőkönyvi átvezetés). Ez önmagában nem teljes production GO. Bizonyíték: [UAT-checkpoint](UAT_CHECKPOINT_2026-08-30.md).

## 15.5 Free (`free`)

Minden foglalás 0 Ft, Tréningterem csoportos is. Óraszám és foglalások riportálási célból megmaradnak.

## 15.6 Pricing precedencia

Egy adott user és hónap fizetendő összegének kötelező precedenciája:

1. ha az effektív pricing policy `Free`, minden foglalás 0 Ft;
2. egyébként, ha a userhez az adott hónapra érvényes Fix óradíj tartozik, a normál órák ezt használják;
3. Fix óradíj hiányában a normál órák a `Sávos` vagy `Progresszív` policy szerint számítódnak;
4. Tréningterem Csoportos használat külön speciális/foglalás-specifikus óradíjon számítódik, **kivéve Free usert**, akinél ez is 0 Ft.

## 15.7 Érvényesség, jövőbeli ütemezés és történet

A pricing policy és a Fix óradíj userenként időben verziózott. Az admin számára a díjazás effektív kezdete elszámolási hónaphoz kötött; új policy/override kezdete hónap első napja. Explicit policy hiányában Sávos.

Jövőbeli mód/díj előre rögzíthető, és egy userhez több egymást követő jövőbeli változás is ütemezhető.

**Egy korábbi kezdőhónapra rögzített új beállítás nem törli automatikusan a már későbbi hónapokra korábban beütemezett változásokat.** A későbbi terv a saját kezdőhónapjától életbe lép, hacsak az admin azt külön nem módosítja. Az admin Díjazás felület ezért minden usernél az összes jövőbeli effektív változást időrendben mutatja, és külön figyelmeztet a későbbi tervek megmaradására.

Azonos kezdőhónaphoz tartozó terv módosítható. Minden tényleges pricing-változás auditált.

Történeti hónap elszámolását a későbbi policy- vagy fixdíj-módosítás nem írhatja át kontrollálatlanul.

Közvetlen, jogosultságot megkerülő Data API/RPC írás tiltott.

---

# 16. Havi órák és fizetendő összeg

A havi számítás Europe/Budapest hónaphatárokkal történik.

Admin havi nézetben userenként látható legalább:
- user;
- összes aktív elszámolandó óra;
- alkalmazott pricing mód / effektív Fix óradíj;
- számított fizetendő összeg;
- releváns Tréningterem speciális díjak.

Több hónap egyszerre választható; hónapok nem olvadhatnak össze.

A számításnak ugyanazt a központi backend/DB üzleti logikát kell használnia minden dashboard/settlement/export útvonalon, hogy eltérő szám ne keletkezhessen ugyanarra az adatra.

---

# 17. Tételes aktív foglalási riport

Admin számára lekérhető összes userre vagy egy userre.

Minimum mezők:
- hónap;
- user;
- dátum;
- helyiség;
- kezdés;
- befejezés;
- óraszám;
- **Foglalás címe**.

Csak aktív foglalások. Cancelled rekord nem jelenhet meg.

Külön részletes CSV export kötelező, a Foglalás címe mezővel.

Ha valamely kiválasztott hónap lekérdezése hibázik, nem szabad hiányos/hamis összesítést vagy exportot generálni; fail-closed hiba szükséges.

---

# 18. Lemondási riport

Külön admin monitoring, nem a havi számlázási riport része.

Időszak: 1/3/6/12 hónap.

Userenként:
- összes eredeti foglalás;
- összes lemondott foglalás;
- lemondott órák;
- user saját lemondási aránya.

Lemondási arány = `user által lemondott foglalások / összes eredeti foglalás × 100`.

Admin törlése megjelenik a lemondott darab/óra adatokban, de nem növeli a user saját lemondási arányát.

Tételes lista minimum:
- user;
- eredeti dátum;
- helyiség;
- kezdés/befejezés;
- lemondott óra;
- lemondás időpontja;
- kezdés előtti időtáv;
- lemondó személy;
- indok.

Összesítő és részletes CSV export külön.

---

# 19. Settlement/történeti pénzügyi snapshot

A havi számítás történetileg reprodukálható legyen. Settlement/revision/booking-line snapshot jellegű modell használható.

Kritikus invariánsok:
- lezárt/történeti revision nem módosítható közvetlenül;
- booking-line snapshot nem írható át utólag kontrollálatlanul;
- fizikai törlés tiltott;
- Tréningterem foglalásonként eltérő 5000/7500/stb. díja külön történeti sorban megőrizhető;
- Free szabály a teljes fizetendőt nullázza, de a foglalási történetet nem törli.

A Befizetések UI jelenleg ki van véve az aktív foglaló rendszerből. Befizetés könyvelése a külön pénzügyi elszámolási folyamatban történik. A már létrejött payment backend/adatmodell **parkoltatott/befagyasztott**: nem törlendő vissza, de ebben a fejlesztési fázisban nem fejlesztendő tovább és nem tekintendő aktív user-facing feature-nek. Későbbi visszaemelése külön üzleti/technikai döntést és saját baseline-t igényel.

---

# 20. Admin felületek – funkcionális minimum

Admin számára elérhető kezelési területek:
- Foglalási naptár;
- Foglalásaim / foglaláskezelés;
- Felhasználók;
- Helyiségek és helyiségcsoportok;
- közvetlen user–room foglalási kivételjogok; a repeat külön, a Felhasználók oldalon user-szintű kapcsoló;
- díjazási policyk és érvényesség;
- havi órák/fizetendő;
- tételes aktív foglalások;
- lemondási riport;
- releváns exportok/beállítások.

`Befizetések` menüpont **nem** része az aktuális aktív navigációnak. Közvetlen régi URL sem adhat használható payment UI-t.

A Fix óradíj admin kezelése implementálva, DB-regresszióval lefedett és manuális staging UAT-n elfogadott (`UAT-PRICING-05/06`). A jövőbeli idővonal `UAT-PRICING-07` tesztje is PASS. Az elfogadott verzió és a további production kapuk az [UAT futási jegyzőkönyvben](UAT_FUTASI_JEGYZOKONYV.md) találhatók.

---

# 21. Auditálás

Kritikus admin és üzleti műveletek auditálandók, legalább:
- szerepkör-változás;
- user aktiválás/deaktiválás;
- onboarding befejezés;
- jogosultság/csoport módosítás;
- pricing policy módosítás;
- Fix óradíj létrehozása/módosítása/megszüntetése;
- Tréningterem egyedi díj módosítása;
- admin más user nevében foglalása;
- foglalás törlés/lemondás;
- settlement/revision kritikus műveletek.

Auditból legyen megállapítható legalább actor, időpont, művelettípus és releváns rekord/előtte-utána üzleti adat, érzékeny auth token/jelszó nélkül.

Audit rekordot alkalmazásból ne lehessen utólag tetszőlegesen átírni vagy fizikailag törölni.

---

# 22. Adatmodell – technológiától független minimális entitások

Egy új implementációnak legalább az alábbi logikai entitásokat kell reprezentálnia:

1. **User/Auth identity** – hitelesítési identitás.
2. **Profile** – név, e-mail kapcsolat, telefon, role, active, onboarding, billing adatok, calendar color, kanonikus user-szintű `can_repeat_bookings`.
3. **Room** – helyiség, aktív állapot, Tréningterem jelleg/speciális attribútumok.
4. **RoomGroup** – adminisztratív helyiségcsoport.
5. **RoomGroupMembership** – room ↔ group.
6. **UserRoomGroup** – user ↔ group tagság.
7. **UserRoomPermission** – közvetlen `can_book` kivételjog; legacy `can_repeat` csak kompatibilitási adat, nem effektív repeat-jogforrás.
8. **Booking** – owner, creator/actor kapcsolat, room, start/end, status, use_type, note, booking_title, series kapcsolat, idempotency, konkurenciaverzió.
9. **BookingSeries** – recurrence definíció, owner, room, szabály, scope.
10. **BookingCancellation** – booking, actor, timestamp, reason, eredeti időadatok.
11. **PricingTier** – órasávok és árak.
12. **UserPricingPolicy** – `tiered/progressive/free` + effective month; a jelenlegi technikai modellben ez választja a számítás fő sémáját.
13. **UserPriceOverride** – **aktív, megtartott Fix óradíj üzleti feature**; userenként és időben érvényes fix normál óradíj. A `Free` policy ezt is felülírja.
14. **SpecialRoomRate / BookingSpecialRate** – Tréningterem default és foglalás-specifikus csoportos díj.
15. **MonthlySettlement** – user+hónap logikai settlement.
16. **SettlementRevision** – verziózott snapshot.
17. **SettlementBookingLine** – foglalásszintű történeti pénzügyi sor.
18. **AuditLog** – append-only kritikus eseménytörténet.
19. **SystemSettings** – globális paraméterek (pl. névláthatóság, default limitek).
20. **BookingEmailOutbox** – egy logikai booking művelethez egy verziózott, deduplikált, retryzható értesítési feladat.
21. **BookingEmailDeliveryAttempt** – append-only kézbesítési próbálkozás és biztonságos hibastátusz.
22. **BookingEmailWorkerRun** – egyszer lezárható, címzett- és payloadmentes worker heartbeat/futásaudit.

A konkrét táblanevek változhatnak, de a történeti és jogosultsági jelentés nem veszhet el.

---

# 23. Adatbázis/biztonsági invariánsok

Új technológiában is kötelező:
- foglalási átfedés atomikus DB-szintű védelme;
- tranzakciók kritikus több-lépéses műveleteknél;
- backend jogosultságellenőrzés;
- deny-by-default érzékeny pénzügyi/történeti tábláknál;
- belső helper műveletek ne legyenek indokolatlanul közvetlen publikus API-k;
- SECURITY DEFINER vagy megfelelő alternatíva esetén explicit, biztonságos search path/context;
- fizikai törlés korlátozása történeti/audit/pénzügyi adatokon;
- audit append-only jelleg;
- idempotencia foglaláslétrehozásnál;
- optimistic concurrency módosításnál;
- atomi foglalás + egyedi Tréningterem-díj;
- Fix óradíj admin módosítása kizárólag kontrollált, auditált backend műveleten keresztül.

---

# 24. Backup/restore és adatmegőrzés – production kötelező tulajdonság

Foglalási vagy elszámolási adat elvesztése elfogadhatatlan.

Production csak akkor indulhat, ha:
- automatikus backup működik;
- off-platform másolat rendelkezésre áll;
- retention dokumentált;
- backup integritás ellenőrzött;
- restore eljárás dokumentált/scriptelt;
- tényleges restore-drill sikeresen végrehajtott;
- restore után foglalási, jogosultsági, audit- és pénzügyi konzisztencia PASS.

Aktuális infrastruktúra-döntési irány: Supabase Free + saját automatizált backup komolyan vizsgált opció; Google Drive megfelelő jelölt off-site tárhelynek. Ez még production readiness döntési folyamat, nem funkcionális feature.

Adatmegőrzési cél: 2 év. Automatikus végleges törlés admin jóváhagyás nélkül nincs.

---

# 25. Export és interoperabilitás

Aktuálisan CSV-alapú admin exportok használatosak a havi és lemondási riportoknál. A részletes havi exportban a Foglalás címe kötelező.

Az adatmodellnek alkalmasnak kell maradnia későbbi:
- XLSX/pénzügyi export;
- számlázó-integráció;
- kihasználtsági statisztika;
- bevételi dashboard;
- további történeti riportok
elkészítésére a meglévő adatokból, utólagos adatvesztő modellváltás nélkül.

---

# 26. Kötelező automatikus/regressziós tesztkészlet

Egy nulláról újraimplementált rendszer nem tekinthető ekvivalensnek legalább az alábbi automatikus tesztek nélkül:

- sikeres normál foglalás;
- 30 perces rács;
- minimum 1 óra;
- nyitvatartás;
- múltbeli egyszeri és ismétlődő foglalás engedélyezése normál usernek és adminnak;
- előrefoglalási limitek;
- jogosulatlan szoba tiltása;
- átfedő foglalás;
- két egyidejű foglalási kísérlet → max. egy siker;
- egymáshoz érő intervallumok engedélyezése;
- idempotens újraküldés;
- módosítás és optimistic concurrency;
- 24 órás user módosítás/lemondás szabály;
- admin törlés;
- ismétlődő napi/heti/kétheti/havi;
- kivételdátum;
- ütközésnél all-or-nothing és skip-conflicts mód;
- DST/helyi idő megőrzés;
- Tréningterem 10 napos user limit;
- Tréningterem repeat user tiltás/admin engedély;
- Tréningterem csoportos default 5000;
- admin egyedi csoportos díj;
- foglalás+díj tranzakció rollback hibánál;
- tiered 20 óra = 20×1900;
- progressive 20 óra = 15×2700 + 5×1900;
- Fix óradíj felülírja a tiered/progressive normál díjat;
- Free felülírja a Fix óradíjat és a Tréningterem speciális díjat is;
- Fix óradíj nem írja felül a nem-Free Tréningterem csoportos speciális díjat;
- Fix óradíj admin-only módosítása, érvényességi hónapja és auditja;
- cancelled booking kizárása;
- pricing policy effective month;
- havi összesítés;
- settlement snapshot/revision immutabilitás;
- booking_title havi részletes riportban;
- user filter a részletes riportban;
- admin-only riporthozzáférés;
- onboarding/adószám szabály;
- utolsó admin védelme;
- room group csak can_book, nem can_repeat;
- privacy/name/color maszkolás;
- auditkritikus műveletek;
- közvetlen tiltott Data API/RPC hozzáférések.

---

# 27. Kötelező manuális UAT / UX ekvivalencia

Automatikus teszt mellett manuálisan is igazolandó legalább:
- desktop napi naptár használhatóság;
- mobil 7 napos sáv;
- havi dátumválasztó;
- sticky órasáv;
- mobil teljes függőleges scroll;
- long press vs scroll;
- iOS/Safari selection tiltás;
- ujjfelengedés → modal;
- `+` gyorsfoglalás;
- normál szobán nincs group selector;
- Tréningteremnél van Egyéni/Csoportos;
- admin csoportos díjmező default 5000 és módosítható;
- mentetlen modal bezárásakor nincs fantom blokk;
- mobil hamburger bezár route-váltáskor;
- foglaló neve/privacy/stabil szín;
- Szerkesztés/Duplikálás/Törlés;
- sorozat scope műveletek;
- onboarding blokkolás és kötelező számlázási adatok;
- CSV user import;
- utolsó admin védelme;
- csoport/közvetlen `can_book` és profil-szintű `can_repeat_bookings` különválasztása;
- Sávos/Progresszív/Free admin policy és effective month;
- **Fix óradíj admin beállítása, effective month, módosítás/megszüntetés**;
- Free precedencia Fix óradíj és Tréningterem felett;
- Tréningterem egyedi csoportos díj;
- Havi órák;
- tételes aktív foglalások Foglalás címe oszloppal;
- részletes CSV;
- lemondási riport;
- payment UI közvetlen régi URL-je nem használható és a Havi órákra/aktív admin oldalra irányít;
- sikeres foglalás UI-visszajelzés és azonnali megjelenés; a kötelező booking e-mail külön transactional outboxból, retryzhatóan kézbesítendő.

---

# 28. Ismert nem-végleges / későbbi elemek

Nem szabad kész feature-ként értelmezni:
- saját foglalások teljes naptárnézetének további fejlesztése;
- ismétlődő kivételdátum Skedda-szerű naptárválasztójának UX finomítása;
- mobil scroll régi, 18:00 körüli megakadás-megjegyzése: aktuális reprodukció vagy célzott végső lezárás nincs igazolva (UAT-UX-05); **nem bizonyított jelenlegi hiba, és nem kívánt/reprodukálásra előírt viselkedés**;
- közvetlen számlázó-integráció;
- befizetések aktív UI-ja;
- teljes statisztikai/vezetői dashboard.

Ezek hiánya nem jogosít fel a már elfogadott baseline funkciók megváltoztatására.

---

# 29. Újraimplementálási elfogadási definíció

Ha a rendszert más kóddal vagy más platformon újraépítjük, akkor csak akkor tekinthető a jelenlegi rendszer funkcionálisan ekvivalens utódjának, ha:

1. a jelen dokumentum minden `kötelező`, `kell`, `nem lehet`, `tiltott` jellegű szabálya teljesül;
2. a jogosultságok backend/DB oldalon is érvényesek;
3. a dupla foglalás konkurens terhelés mellett sem lehetséges;
4. a díjszámítás ugyanazokat az eredményeket adja, beleértve a Sávos/Progresszív/Fix/Free precedenciát és a Tréningterem szabályait;
5. a történeti settlement/audit adatok nem írhatók át kontrollálatlanul;
6. a mobil és desktop foglalási UX a BOOKING_UI_UX_BASELINE elfogadott működésével ekvivalens;
7. a kötelező automatikus tesztkészlet zöld;
8. a funkcionális UAT zöld, nincs P1/P2 eltérés;
9. backup és tényleges restore-drill bizonyított;
10. production monitoring/heartbeat és riasztás kontrollált teszttel bizonyított;
11. kritikus biztonsági/pénzügyi részek független második review-t kapnak;
12. production csak explicit üzleti GO jóváhagyással indul.

---

# 30. Változáskezelés

Ez a dokumentum a rendszer **kanonikus funkcionális baseline-ja**. Új üzleti döntés vagy elfogadott feature esetén ugyanabban a fejlesztési körben frissíteni kell.

Ha a forráskód és ez a dokumentum eltér:
- stagingen elfogadott új, dokumentált üzleti döntés esetén a dokumentum frissítendő;
- véletlen kódregresszió esetén a kód javítandó;
- eltérés nem oldható fel feltételezéssel.

A production release dokumentációjának hivatkoznia kell arra a baseline verzióra/commitra, amely ellen a release-t elfogadtuk.
