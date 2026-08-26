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

## Foglalási e-mail státusz
Automatikus booking confirmation e-mail **nem go-live blocker és nem kötelező az első production verzióban**.

Kötelező viszont:
- sikeres foglalás egyértelmű UI-visszajelzése;
- azonnali megjelenés a naptárban/Foglalásaimban;
- sikertelen foglalás ne jelenjen meg sikeresként.

E-mail értesítés későbbi fejlesztési lehetőség.

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
- mobil Skedda-minta részletes leírása: `docs/skedda-mobile-calendar-ux.md`.

A baseline-ban rögzített, már elfogadott UI/UX funkciót vagy gesztust későbbi refaktor nem távolíthat el külön dokumentált döntés nélkül.

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

A független review után véglegesen elfogadott:
- a **Fix óradíj** megtartása negyedik admin üzleti díjazási lehetőségként, érvényességi hónappal;
- a régi FS v1.0 **SUPERSEDED** státusza;
- a booking confirmation e-mail nem go-live blocker;
- a payment backend parkoltatott/befagyasztott.

A kanonikus baseline ezeket tartalmazza. A Fix óradíj dedikált admin RPC/UI-ja és auditált backend útja elkészült; az automatikus DB/regressziós tesztek zöldek. A funkció staging manuális UAT-ja továbbra is production readiness kapu, de az RPC/UI hiánya már nem production gap.

A jövőbeli díjazási tervek megtartása tudatos működés: egy korábbi kezdőhónap módosítása nem törli a későbbre már beütemezett változásokat. Ezeket az admin teljes idővonalként látja.

Részletes döntés: `docs/DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md`.
Review-feldolgozás: `docs/CLAUDE_BASELINE_REVIEW_RESOLUTION_2026-08-26.md`.

Részletes infrastruktúra checkpoint: `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md`.
Production readiness checklist: `docs/PRODUCTION_READINESS_CHECKLIST.md`.

Production továbbra is tilos a nyitott production blockerek lezárása, sikeres backup automatizálás, tényleges restore-drill, monitoring/alert teszt, teljes regresszió, kritikus független review és explicit üzleti jóváhagyás nélkül.

## Nem MVP / későbbi fejlesztés
- bankkártyás fizetés
- SSO/SAML
- membership
- discount codes
- floor plan
- add-ons
- natív mobilapp
- komplex notification engine
- automatikus booking confirmation e-mail
- közvetlen számlázó-integráció
- befizetések aktív UI-ja
- teljes statisztikai dashboard

## Új fejlesztési beszélgetés indítása
Az új fejlesztési beszélgetés első feladata:
1. **kötelezően** áttekinteni ezt a projektkontextust és a `docs/CURRENT_FUNCTIONAL_BASELINE.md` aktuális verzióját; a régi FS v1.0 csak történeti/SUPERSEDED forrás;
2. kötelezően áttekinteni a `docs/DECISION_2026-08-26_CLAUDE_REVIEW_FOLLOWUP.md` és `docs/CLAUDE_BASELINE_REVIEW_RESOLUTION_2026-08-26.md` dokumentumokat, amíg tartalmuk teljesen be nem olvad a release-baseline-ba;
3. foglalási/UI feladat esetén kötelezően áttekinteni a `docs/BOOKING_UI_UX_BASELINE.md` és `docs/skedda-mobile-calendar-ux.md` fájlokat;
4. production infrastruktúra feladat esetén kötelezően áttekinteni a `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md` és `docs/PRODUCTION_READINESS_CHECKLIST.md` fájlokat;
5. az aktuális technikai architektúra- és adatmodelldokumentumot áttekinteni;
6. a GitHub repository aktuális branch/PR állapotát ellenőrizni; productionre csak review-zott, stagingen elfogadott állapot kerülhet;
7. új fejlesztés előtt ellenőrizni, hogy az nem okoz-e regressziót a baseline-ban rögzített működésben.
