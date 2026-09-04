# A-Hely saját foglalási rendszer – projektkontextus

## Cél
Az A-Hely jelenlegi AllBooked/Skedda rendszerének kiváltása saját, webalapú foglalási és elszámolási rendszerrel. A rendszer legyen egyszerű, mobilon is jól használható, biztonságos, auditálható, és kezelje a havi elszámolást is.

## Kanonikus funkcionális forrás
A jelenlegi rendszer elsődleges funkcionális és újraimplementálási specifikációja:

`docs/CURRENT_FUNCTIONAL_BASELINE.md`

Az `A-Hely_Foglalasi_Rendszer_Funkcionalis_Specifikacio_v1.0.docx` **történeti / SUPERSEDED** dokumentum. Nem használható önálló vagy elsődleges implementációs forrásként, mert több pontját későbbi üzleti döntések felülírták.

A 2026-08-26-i Claude-review és az arra adott tulajdonosi döntések kötelező kiegészítő forrásai:
- `docs/DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md`;
- `docs/CLAUDE_BASELINE_REVIEW_RESOLUTION_2026-08-26.md`.

A 2026-09-03-i PWA/e-mail/migráció/mobil UX döntések és UAT-eredmények kötelező kiegészítő forrása:
- `docs/WORKLOG_2026-09-03_PWA_EMAIL_MIGRATION_MOBILE_UX.md`.
- `docs/DECISION_2026-09-03_BOOKING_EMAIL_OUTBOX.md`.

## Szerepkörök
**Admin:** userek, helyiségek, jogosultságok, árak, foglalási szabályok, foglalások, elszámolás, export és beállítások kezelése.

**Normál user:** csak az engedélyezett helyiségeket és foglalásokat látja; foglalhat, saját foglalását szabály szerint módosíthatja/törölheti; ismétlődő foglalás csak engedélyezett keretek között. A havi elszámolási dashboard userenként ki- és bekapcsolható. Más foglalók nevének láthatósága **globális admin beállítás**, nem userenkénti kapcsoló; kikapcsolva más user neve és stabil azonosító színe sem kerülhet ki normál usernek.

## Helyiségek
- Tréningterem
- 1.Szoba-családi
- 2.Szoba
- 3.Szoba
- 4.Szoba
- 5.Szoba
- 6.Szoba
- Gyerek szoba
- Pitypang szoba
- Csoport szoba
- Forrás tér

## Foglalási alapparaméterek
- Magyar nyelv, Europe/Budapest, HUF.
- Nyitvatartás: 07:00–22:00.
- Időegység: 30 perc.
- Minimum foglalás: 1 óra.
- Default előrefoglalás: 90 nap, központi paraméter, userenként felülírható.
- A rendszer legalább 1 évre előre biztonságosan kezeljen foglalást.
- Ismétlődés: napi, heti, kétheti, havi; vége/darabszám; kivételdátumok.
- Ütközés esetén a user dönthessen a szabad alkalmak létrehozása vagy a teljes sorozat megszakítása között.

## Tréningterem
- Normál user max. 10 napra előre foglalhat; ez admin által állítható.
- Ismétlődő Tréningterem-foglalást csak admin hozhat létre.
- Egyéni használat: user normál díjazása.
- Csoportos használat: default 5000 Ft/óra; admin foglalásonként felülírhatja az óradíjat.
- Admin egyedi csoportos díja és a foglalás/sorozat létrehozása egy adatbázis-tranzakcióban történjen; félkész foglalás nem maradhat vissza díjrögzítési hiba esetén.
- Tréningterem admin foglalásánál a foglalás címe üzletileg fontos; a havi tételes aktív foglalási lekérdezés és a részletes export tartalmazza.

## Lemondás
- Normál user 24 órán belül már nem törölhet.
- Admin bármikor törölhet.
- Admin által törölt foglalás nem kerül az elszámolásba.
- A törlésről auditrekord marad.
- Havi statisztika: törölt foglalások száma és a törlés előtti idő; részletes lista is lekérhető.

## Díjazás
Az admin userenként négy üzleti díjazási lehetőség közül választhat:
- **Sávos** – default;
- **Progresszív**;
- **Fix óradíj**;
- **Free / 0 Ft**.

Default havi **sávos** díjazás: a hónap teljes elszámolandó normál óraszáma meghatározza az összes normál órára alkalmazott óradíjat.
- 1–15 óra: 2700 Ft/óra
- 16–60 óra: 1900 Ft/óra
- 61 órától: 1700 Ft/óra

Progresszív módban a sávok külön-külön árazódnak (például 20 óránál az első 15 óra 2700 Ft, a következő 5 óra 1900 Ft).

Fix óradíjnál a user normál órái az adott hónapra érvényes fix óradíjon számolódnak. A jelenlegi technikai modell ezt `user_price_overrides` réteggel kezeli. A Fix óradíj **nem** írja felül a nem-Free Tréningterem csoportos speciális díját.

Precedencia:
1. `Free` → minden foglalás 0 Ft;
2. egyébként érvényes Fix óradíj → normál órák fix díjon;
3. fix override hiányában Sávos/Progresszív;
4. Tréningterem Csoportos külön speciális/foglalás-specifikus díj, kivéve Free usert.

Userenként időbeli érvényességgel díjszabás állítható be. Az érvényességi dátumok miatt a történeti elszámolásnak reprodukálhatónak kell maradnia.

A Fix óradíj biztonságos, auditált admin RPC/UI kezelése elkészült: az admin a módot, a Ft/óra értéket és az érvényességi hónapot a Díjazás felületen állíthatja. A kliensoldal egyetlen módosítási belépési pontja az egységes `admin_set_user_pricing_configuration`; a belső policy-helper közvetlen authenticated végrehajtása tiltott.

Egy userhez több egymást követő jövőbeli díjazási változás előre beütemezhető. Egy korábbi kezdőhónapra rögzített új beállítás **nem törli automatikusan** a már későbbi hónapokra korábban beütemezett változásokat; azok a saját kezdőhónapjuktól életbe lépnek, hacsak az admin külön nem módosítja őket. Az admin Díjazás felület az összes jövőbeli effektív változást időrendben mutatja és erre külön figyelmeztet.

## Havi user dashboard
Userenként kapcsolható. Mutassa:
- havi foglalások számát;
- havi óraszámot;
- aktuális/becsült fizetendőt;
- lezajlott és hátralévő órákat;
- havi részletes foglalási listát.

A díjszabás miatt a hónap közbeni fizetendő összeg változhat.

## Elszámolás – aktuális scope döntés
A foglalórendszer a foglalásokból számolja a havi óraszámot és fizetendő összeget. Ami aktív foglalásként benne van a rendszerben, elszámolandó; ami törölve/lemondva van, nem szerepel az elszámolásban.

A **Befizetések UI jelenleg nem része az aktív foglaló rendszer scope-jának.** A befizetés rögzítése a külön pénzügyi elszámolási projekt/folyamat része. A korábban elkészült payment DB-réteg nincs visszatörölve, de **parkoltatott/befagyasztott**, az alkalmazás navigációjából és aktív UI-jából ki van véve, és ebben a fázisban nem fejlesztendő tovább.

A havi összesítés és settlement/audit történeti adatai továbbra is úgy készüljenek, hogy későbbi pénzügyi feldolgozás és export megbízhatóan elvégezhető legyen.

## Foglalási e-mail státusz – 2026-09-03-i új döntés
A korábbi „booking confirmation e-mail nem go-live blocker” döntést a projektgazda **felülírta**.

Mostantól kötelező, hogy a foglalás tulajdonosa e-mailt kapjon minden sikeres:
- új foglalás;
- foglalásmódosítás;
- törlés/lemondás

után, függetlenül attól, hogy a műveletet ő maga vagy admin végezte.

Ismétlődő/sorozatos műveletnél **egy összefoglaló e-mail** küldendő, nem külön levél minden alkalomról.

Az e-mail küldési hiba nem veszélyeztetheti a már sikeres foglalási tranzakciót. Preferált technikai minta: tartós transactional outbox + külön retry-képes küldő folyamat + auditálható küldési státusz.

Feladó és Reply-To: `foglalas@a-hely.com`. A MediaCenter által igazolt SMTP host `pop3.mediacenter.hu` (nem elírás), SSL/TLS port 465, teljes e-mail címes felhasználónévvel és kötelező hitelesítéssel. A díjmentes szolgáltatás napi 100 levélre és levelenként 10 címzettre korlátozott; production előtt a terhelési tartalékot vagy a külön privát SMTP csomagot igazolni kell. SMTP jelszó/secrets csak biztonságos runtime/GitHub environment secretként kezelhetők, chatbe/repositoryba nem kerülhetnek.

A #111 draft ágon elkészült az outbox, a booking RPC-k tranzakcióvégi enqueue-integrációja, a magyar renderer, a verzióra rögzített Nodemailer-kliens, a Bearer tokennel védett Node.js worker Route Handler, az append-only worker heartbeat audit és az admin-only, érzékeny adatot nem visszaadó kézbesítési monitor. A runtime alapértéke `BOOKING_EMAIL_MODE=disabled`, amely nem claimel, nem küld és nem ír heartbeatot. A 2026-09-04-i automatikus staging deploy #14 sikeresen alkalmazta a cutoff-guard és a három booking-email migrációt; a local/remote history egyezik, a deploy utáni dry-run szerint a remote adatbázis naprakész. A branch-scope Preview konfiguráció `capture` módban, SMTP-változók nélkül elkészült. Az admin-only capture indító `bc68e22` commitján Application checks #591, Database tests #540 és Vercel Preview PASS. A teljes SMTP nélküli capture UAT 16/16 `captured` rekorddal, nulla sent/retry/dead-letter/provider Message-ID eredménnyel PASS; egyedi, admin-owner-routing, `series`, `occurrence`, `following` és üres no-op futás is igazolt. Scheduler és valós SMTP UAT még nyitott; main merge és production deploy nem történt.

GitHub issue: #107. Részletek: `docs/WORKLOG_2026-09-03_PWA_EMAIL_MIGRATION_MOBILE_UX.md` és `docs/DECISION_2026-09-03_BOOKING_EMAIL_OUTBOX.md`.

## Migráció – 2026-09-03-i scope döntés
A jelenlegi AllBooked/Skedda rendszerből a migráció során kötelezően át kell emelni:
- a migráció hónapjának **teljes adatait a hónap első napjától**;
- minden jövőbeli szükséges adatot és foglalást.

Példa: október 15-i éles átállásnál október 1-től kezdődő szükséges adatok + minden jövőbeli adat migrálandó.

A migráció nem egyszeri kézi DB-beírás: scriptelt, újrafuttatható, dry-run képes, idempotens import szükséges, dokumentált forrás→cél mappinggel, duplikációvédelemmel, ütközésriporttal, staging próbamigrációval és forrás/cél reconciliationnel. Production import előtt friss backup és visszaállítható rollback/restore terv kötelező.

GitHub issue: #108. A pontos mezőmapping a tényleges AllBooked/Skedda user/booking exportminták alapján véglegesítendő.

## Export
A havi/tételes exportnak tartalmaznia kell a pénzügyi feldolgozáshoz szükséges adatokat. A tételes aktív foglalások és a részletes CSV tartalmazza a `Foglalás címe` mezőt is.

Későbbi számlázó-integráció és további pénzügyi exportok a történeti adatokból legyenek megvalósíthatók.

## Kihasználtsági/stat modul – 2. fázis
Az adatmodell indulástól támogassa:
- helyiségenkénti kihasználtság;
- napi/heti/havi/éves kihasználtság;
- idősávkihasználtság;
- bevétel helyiségenként;
- átlagos realizált óradíj;
- aktív userek;
- userenkénti havi/éves óraszám;
- havi/éves trendek;
- vezetői dashboard.

## Adatbiztonság – kritikus
Foglalási vagy elszámolási adat elvesztése nem elfogadható.

Kötelező:
- automatikus backup;
- visszaállíthatóság;
- adatbázis-tranzakciók;
- adatbázis-szintű ütközésvédelem;
- backend jogosultságellenőrzés;
- auditnapló;
- technikai hibalog;
- production működés proaktív monitoringja/heartbeatje és riasztása.

Adatmegőrzési cél: 2 év.
A tervezett törlés előtt admin figyelmeztetés: 30 / 15 / 5 / 1 nappal.
Automatikus végleges törlés helyett admin jóváhagyása szükséges.

## Production monitoring
A production rendszer hibáját vagy súlyos lassulását nem a usernek kell elsőként észlelnie.

Production előtt kötelező kialakítani és kontrollált teszttel bizonyítani:
- külső uptime/heartbeat monitort;
- biztonságos health endpointot;
- alkalmazás + DB/Supabase elérhetőség ellenőrzést;
- válaszidő figyelést;
- kritikus hibamonitoringot;
- backup heartbeatet;
- automatikus riasztást és recovery értesítést;
- a monitoring hostingtól való megfelelő függetlenségét.

Részletek: `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md`.

## UI
- reszponzív webapp;
- magyar;
- napi többoszlopos naptár;
- saját foglalás külön színnel;
- admin és user felület elkülönítve;
- a normál user foglalási UX a Skedda/AllBooked megszokott használati logikáját kövesse, hogy a váltás minimális újratanulást igényeljen;
- a stagingen elfogadott részletes UI/UX baseline kötelező referencia: `docs/BOOKING_UI_UX_BASELINE.md`;
- mobil Skedda-minta részletes leírása: `docs/skedda-mobile-calendar-ux.md`;
- a normál mobil menüoldalakon az oldal törzse ne legyen oldalirányban görgethető; formok és admin struktúrák törjenek viewporton belül;
- minden normál mobil oldal legfelső `page-heading` szövegblokkja egységes belső bal pozícióban induljon; a foglalási naptár speciális fejléce kivétel;
- nagy admin táblák mobilon szükség esetén kártyás nézetre válthatnak úgy, hogy üzleti/pénzügyi adat ne vesszen el.

A baseline-ban rögzített, már elfogadott UI/UX funkciót vagy gesztust későbbi refaktor nem távolíthat el külön dokumentált döntés nélkül.

### PWA – aktív webes scope
A PWA 2026-09-03-tól aktív scope. A PWA **nem natív mobilapp**, hanem a meglévő Next.js webalkalmazás telepíthető/standalone megjelenési módja.

Első PWA-verzió:
- online-first;
- nincs offline üzleti adatírás;
- nincs booking/auth/Supabase/API response cache;
- nincs background sync üzleti íráshoz;
- offline állapotban egyértelmű fallback, stale foglalási naptár nem jelenhet meg aktuális adatként;
- biztonságos statikus app-shell cache-elhető;
- iOS/Android/desktop install/UAT szükséges.

Issue #105, draft PR #106. Az iPhone telepítés/standalone és offline fallback UAT PASS; Android/Chromium és hálózat-visszatérés ellenőrzése még külön szükséges.

## Javasolt technológiai irány
Kiindulási javaslat:
- Next.js / React
- PostgreSQL
- Supabase auth + adatbázis/jogosultsági alap
- szerveroldali üzleti logika
- GitHub
- automatikus tesztek
- staging + production

A végleges production hosting és backup infrastruktúra még production readiness döntési pont. Részletes checkpoint: `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md`.

## Fejlesztési munkamód
1. kanonikus baseline / aktuális üzleti követelmény;
2. technikai architektúra;
3. adatmodell;
4. GitHub repository és issue-k;
5. implementáció;
6. automatikus tesztek;
7. független AI/Claude review;
8. javítás;
9. üzleti baseline szerinti ellenőrzés;
10. staging;
11. élesítés.

Különösen szigorú review kell a foglalási motorra, ütközésvédelemre, jogosultságokra, Sávos/Progresszív/Fix/Free díjszámításra, elszámolásra, backupra, restore-ra és monitoringra.

## 2026-08-18-i fejlesztési sorrend döntés

A napi foglalási működés a Skedda kiváltásának legfontosabb feltétele. A backup/restore stratégiai baseline elkészült, de a tényleges production backup automatizálás a teljes funkcionális elfogadási teszt után folytatódik.

Aktuális sorrend:
1. teljes funkcionális UAT a jóváhagyott foglalási működésre;
2. minden P1/P2 funkcionális eltérés javítása és regressziós tesztje;
3. annak kimondása, hogy a rendszer funkcionálisan alkalmas a Skedda kiváltására;
4. production backup/off-site mentés implementáció;
5. sikeres teljes restore-drill;
6. staging elfogadás;
7. production élesítés.

A backup és restore követelmény nem enyhül: tényleges backup és sikeres restore-drill nélkül production indulás nem megengedett.

## 2026-08-20-i foglalási UI/UX baseline döntés

A staging UAT és a Skedda mobil/desktop összehasonlítás alapján a már kialakított foglalási UX regresszióvédett projektkövetelménnyé vált.

Kötelezően megőrzendő fő elemek:
- napi többhelyiséges naptár, 07:00–22:00;
- desktopon tömör, Skedda-szerű napi képernyőkihasználás;
- mobilon 7 napos felső dátumsáv és külön havi naptárválasztó;
- mobilon sticky bal órasáv vízszintes görgetésnél;
- mobilon természetes függőleges scroll a teljes naptárfelületen;
- mobil foglaláskijelölés long press után, nem azonnali érintésre;
- kijelölés után ujjfelengedéskor azonnal nyíló foglalási modál;
- iOS/Safari natív szövegkijelölés tiltása a naptárgesztus közben;
- jobb alsó fix `+` gyorsfoglalás mobilon és desktopon;
- ismétlődő foglalás ugyanabban a foglalási ablakban, nem külön főoldali mobil folyamatként;
- normál szobák használata mindig Egyéni; Egyéni/Csoportos választó csak Tréningteremnél;
- Tréningterem helyiségnév csak egyszer jelenjen meg;
- mobil kompakt A-Hely + hamburger navigáció, amely menüpont választásakor bezár;
- egész órás vízszintes rácsvonal hangsúlyosabb, félórás finomabb; óracímkék az egész órás vonalakhoz igazodnak.

A részletes technikai és regressziós checklist forrása: `docs/BOOKING_UI_UX_BASELINE.md`.

## 2026-08-25-i funkcionális fáziszárás és production readiness checkpoint

A staging UAT alapján a 2026-08-25-i fejlesztési fázis fő funkcionális scope-ja lezárult. Új, nem szükséges üzleti funkció fejlesztése helyett a következő szakasz a production infrastruktúra és élesítési biztonság bizonyítása.

Lezárt üzleti döntések:
- default Sávos; opcionális Progresszív, Fix óradíj és Free díjazás userenként, érvényességi idővel;
- Tréningterem csoportos default 5000 Ft/óra, admin foglalásonként felülírhatja;
- Tréningterem admin foglalás címe szerepel a havi tételes lekérdezésben/exportban;
- Befizetések UI kivéve a foglaló rendszer aktív scope-jából.

Production review során az egyedi Tréningterem-díj rögzítését atomi tranzakcióvá tettük, és security hardening készült.

Infrastruktúra döntési irány:
- Supabase Free production komolyan vizsgált opció saját professzionális backup/restore rendszerrel;
- Google Drive megfelelő jelölt az off-platform mentések tárolására;
- Supabase Pro nem kötelező kiindulási feltétel, de későbbi upgrade opció;
- Vercel Pro költsége miatt alternatív hosting külön vizsgálandó;
- Cloudflare Workers jelenleg blokkolt a Next.js 16 `proxy.ts` támogatási/kompatibilitási kockázata miatt;
- következő vizsgálati fókusz: Netlify és más üzleti használatra alkalmas, olcsó Next.js hosting alternatívák.

## 2026-08-26-i Claude-review döntések

A független review után akkor véglegesen elfogadott:
- a **Fix óradíj** megtartása negyedik admin üzleti díjazási lehetőségként, érvényességi hónappal;
- a régi FS v1.0 **SUPERSEDED** státusza;
- a booking confirmation e-mail akkor még nem volt go-live blocker;
- a payment backend parkoltatott/befagyasztott.

**Megjegyzés:** a booking e-mailre vonatkozó 2026-08-26-i döntést a 2026-09-03-i tulajdonosi döntés felülírta; lásd a fenti „Foglalási e-mail státusz” részt és a 2026-09-03-i munkanaplót.

A kanonikus baseline 2026-09-03-án szinkronizálva lett a kötelező booking e-mail döntéssel. A Fix óradíj dedikált admin RPC/UI-ja és auditált backend útja elkészült; az automatikus DB/regressziós tesztek zöldek. A funkció staging manuális UAT-ja a 2026-08-30-i átvezetés szerint már elfogadott (UAT-PRICING-05/06); sem az RPC/UI, sem ennek a célzott UAT-ja nem nyitott hiány. A teljes production readiness ettől külön kapu marad.

A jövőbeli díjazási tervek megtartása tudatos működés: egy korábbi kezdőhónap módosítása nem törli a későbbre már beütemezett változásokat. Ezeket az admin teljes idővonalként látja.

Részletes döntés: `docs/DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md`.
Review-feldolgozás: `docs/CLAUDE_BASELINE_REVIEW_RESOLUTION_2026-08-26.md`.

Részletes infrastruktúra checkpoint: `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md`.
Production readiness checklist: `docs/PRODUCTION_READINESS_CHECKLIST.md`.

Production továbbra is tilos a nyitott production blockerek lezárása, sikeres backup automatizálás, tényleges restore-drill, monitoring/alert teszt, teljes regresszió, kritikus független review és explicit üzleti jóváhagyás nélkül.

## 2026-08-30-i UAT-eredményátvezetés és részleges fáziszárás

A projektgazda által már elfogadott eredmények bekerültek az [UAT futási jegyzőkönyvbe](docs/UAT_FUTASI_JEGYZOKONYV.md), a checklist v1.3 mind a 98 azonosítójával szinkronban.

- Tesztelt alkalmazáskód: `457363609ffac54555a7a17b1cde7742eec5b60e`, `feature/82-pricing-modes`, PR #90.
- Helyesbített nyilvántartás: **50 tételes PASS, 22 korábbi modul/UI-elfogadás, 1 döntéssel lezárt eset, 22 részleges/tisztázandó bizonyíték és 3 blokkolt production drill**. Az előzetes 36/59/3 összesítés hiányos volt; az új számok nem új UAT-futtatásból származnak.
- AUTH-01–05, CAL-01–03, CANCEL-01/02 és TRAIN-03/04 korábbi elfogadása visszakeresve; BOOK-11 és EDIT-05 megfelelő automatikus bizonyítékkal lezárva. Az elfogadott admin/onboarding/UI-modulok nem újrakezdendő tesztek.
- Az ADMIN-07 és a baseline/architektúra ismétlési jogra vonatkozó leírása a már elfogadott PR #77-hez igazítva: profil-szintű repeat + effektív can_book + normál helyiség, nem kizárólag közvetlen per-room repeat.
- **PRICING-01–07, MONTH-01–05, CSV-01–03, SETTLE-01–02: 17/17 PASS**, a megkezdett elszámolási tesztlánc lezárult.
- A múltbeli egyedi/sorozatos foglalás két hiányzó jegyzőkönyvi sora (BOOK-14, REC-09A) és a már elfogadott foglalási/UX-eredmények is átvezetve.
- Ugyanezen forrásfán Application CI: 86 teszt + typecheck/build PASS; Database CI: 615 pgTAP-ellenőrzés + konkurencialépések/schema lint PASS.
- A korábbi Claude 6 review a `63748919aaa0c2458277536643f79b37efd0bf7c` verzió és PR #91 scope-jában lezárt. Ez nem automatikus review-jóváhagyás a későbbi változásokra.
- Teljes funkcionális GO, main merge és production deploy nincs jóváhagyva. A fennmaradó UAT-bizonyítékok, a végleges release review-ja, hosting/config, backup/restore és monitoring kapuk külön nyitottak.

Részletes, esetenkénti források és bizonyítékhatárok: [UAT-bizonyítékegyeztetés](docs/UAT_BIZONYITEK_EGYEZTETES_2026-08-30.md), [checkpoint](docs/UAT_CHECKPOINT_2026-08-30.md). A már elfogadott teszteket ne indítsuk újra pusztán a régi jegyzőkönyv hiányos állapota miatt.

## 2026-09-03-i PWA / e-mail / migráció / mobil UX checkpoint

Részletes forrás: `docs/WORKLOG_2026-09-03_PWA_EMAIL_MIGRATION_MOBILE_UX.md`.

Aktuális állapot:
- PWA issue #105 / draft PR #106: iPhone install/standalone/offline fallback PASS; Android/Chromium és hálózat-visszatérés UAT még nyitott;
- kötelező e-mail issue #107 / draft PR #111: minden create/update/delete után a booking owner kap levelet, admin műveletnél is; sorozatnál 1 összefoglaló e-mail; elkészült a verziózott outbox, lease/retry/dead-letter RPC, a booking műveletek tranzakcióvégi enqueue-integrációja, a magyar text/HTML renderer, a verzióra rögzített Nodemailer-kliens, a Bearer tokennel védett Node.js worker Route Handler, az append-only heartbeat audit, az admin-only kézbesítési monitor, a capture-only admin indító és a staging capture runbook; helyben 23 tesztfájl / 134 teszt, typecheck és build PASS; a 2026-09-04-i automatikus staging deploy #14 alkalmazta a cutoff-guard és a három booking-email migrációt, az utóellenőrzés és a megismételt no-op deploy #15 PASS; az admin indító commitján Application checks #591, Database tests #540 és Vercel PASS; a teljes SMTP nélküli staging capture UAT 16/16 rekorddal és idempotens üres futással PASS; scheduler és valós SMTP UAT még nyitott;
- migráció issue #108: migráció hónapjának teljes adatai + minden jövőbeli adat; dry-run/idempotens/staging + reconciliation kötelező;
- mobil UX issue #109 / draft PR #110: Adataim/Foglalásaim/Felhasználók/Havi órák és fizetendő/Díjazás/Hozzáférések/Helyiségek reszponzív javításai folyamatban; iPhone-on a Havi órák hónapválasztó és a Helyiségcsoportok levágási hibája célzottan PASS;
- a #109 hátralévő forrásauditjában a Beállítások oldalhoz nem kellett külön javítás; a Lemondások összesítő és tételes táblái mobil kártyanézetet, a záró hónap pedig iOS-biztos Év + Hónap választót kapott; a Lemondások célzott iPhone UAT PASS („Működik”), valós Android Chrome UAT még szükséges;
- valós Android Chrome smoke UAT továbbra is szükséges, iPhone PASS nem automatikus Android PASS;
- a stagingben `Mhely` néven szereplő inaktív csoportnak nincs aktuális user- vagy szobakapcsolata, de audit-előzménye van; támogatott törlő RPC/UI nincs, ezért nem töröltük. Alapértelmezett ajánlás az inaktiválás; külön végleges törlés csak explicit döntéssel, dependency-ellenőrzött és auditált tranzakcióként készülhet.
- a 2026-09-04-i staging promóciós döntés megszünteti a mindennapos GitHub Actions kézi indítást: zöld Application/Database CI, elvárt dry-run és kifejezett staging-jóváhagyás után a pontos commit force nélkül a dedikált `staging` branchre kerül; ez automatikus dry-run → staging DB deploy → utóellenőrzést indít. A remote secret kizárólag a GitHub `staging` Environmentben használható, PR nem kapja meg. Main merge és production deploy változatlanul külön, kifejezett jóváhagyást igényel. Részletesen: `docs/DECISION_2026-09-04_STAGING_PROMOTION_AUTOMATION.md`.

## Nem MVP / későbbi fejlesztés
- bankkártyás fizetés
- SSO/SAML
- membership
- discount codes
- floor plan
- add-ons
- natív mobilapp
- komplex, általános notification engine a most kötelező booking e-mailen túl
- közvetlen számlázó-integráció
- befizetések aktív UI-ja
- teljes statisztikai dashboard

## Új fejlesztési beszélgetés indítása
Az új fejlesztési beszélgetés első feladata:
1. **kötelezően** áttekinteni ezt a projektkontextust és a `docs/CURRENT_FUNCTIONAL_BASELINE.md` aktuális verzióját; a régi FS v1.0 csak történeti/SUPERSEDED forrás;
2. kötelezően áttekinteni a `docs/DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md` és `docs/CLAUDE_BASELINE_REVIEW_RESOLUTION_2026-08-26.md` dokumentumokat, amíg tartalmuk teljesen be nem olvad a release-baseline-ba;
3. kötelezően áttekinteni a `docs/WORKLOG_2026-09-03_PWA_EMAIL_MIGRATION_MOBILE_UX.md` és e-mail feladatnál a `docs/DECISION_2026-09-03_BOOKING_EMAIL_OUTBOX.md` dokumentumot;
4. foglalási/UI feladat esetén kötelezően áttekinteni a `docs/BOOKING_UI_UX_BASELINE.md` és `docs/skedda-mobile-calendar-ux.md` fájlokat;
5. production infrastruktúra feladat esetén kötelezően áttekinteni a `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md` és `docs/PRODUCTION_READINESS_CHECKLIST.md` fájlokat;
6. az aktuális technikai architektúra- és adatmodelldokumentumot áttekinteni;
7. a GitHub repository aktuális branch/PR állapotát ellenőrizni; productionre csak review-zott, stagingen elfogadott állapot kerülhet;
8. új fejlesztés előtt ellenőrizni, hogy az nem okoz-e regressziót a baseline-ban rögzített működésben;
9. UAT folytatásakor elolvasni a `docs/UAT_FUTASI_JEGYZOKONYV.md`, `docs/UAT_BIZONYITEK_EGYEZTETES_2026-08-30.md` és `docs/UAT_CHECKPOINT_2026-08-30.md` eredményeit; a már elfogadott teszteket nem automatikusan újrafuttatni. A 22 egyeztetendő sor sem 22 új kézi teszt: előbb meglévő forrás/assertion és releváns változás, csak utána indokolt célzott pótlás.
