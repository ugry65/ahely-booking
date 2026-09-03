# 2026-09-03 – PWA, e-mail értesítés, migráció és mobil UX munkanapló

## Cél
Ez a dokumentum a 2026-09-02/03-i fejlesztési beszélgetésben meghozott üzleti döntéseket, elkészült fejlesztési egységeket, UAT-eredményeket és nyitott következő lépéseket rögzíti. A cél, hogy a projekt következő beszélgetése a teljes chatelőzmény nélkül is pontosan folytatható legyen.

## 1. Kiinduló branch / release-helyzet

A mobil naptár #98 javítása korábban valós mobil UAT PASS-t kapott, a PR #99 a `feature/82-pricing-modes` branchbe merge-ölve lett. A `main` branchbe és productionbe nem történt merge/deploy.

A mostani fejlesztések külön egységekben készülnek:

- PWA: issue #105, draft PR #106, branch `feature/105-pwa`, base `feature/82-pricing-modes`;
- mobil reszponzív menüoldalak: issue #109, draft PR #110, branch `fix/109-mobile-responsive-pages`, base `feature/82-pricing-modes`;
- kötelező booking e-mail: issue #107;
- migráció: issue #108.

Sem #106, sem #110 nincs `main`-be merge-ölve, production deploy nem történt.

---

## 2. PWA – új aktív scope

### Üzleti döntés

A meglévő A-Hely webalkalmazás Progressive Web App képességet kap. Ez **nem natív mobilapp**, hanem ugyanaz a Next.js webalkalmazás telepíthető/standalone megjelenésben.

A `CURRENT_FUNCTIONAL_BASELINE.md` azon állítása, hogy natív mobilapp nincs scope-ban, továbbra is igaz. A PWA ettől külön, aktív webes scope.

### Első PWA-verzió biztonsági szabályai

- online-first működés;
- nincs offline foglalás, módosítás vagy törlés;
- nincs offline admin/pénzügyi adatírás;
- nincs üzleti adatírás background sync-kel;
- Supabase/API/auth/foglalási/jogosultsági/audit/elszámolási válaszok nem cache-elhetők tartósan service workerből;
- session/token nem kerül service-worker tárolásba;
- másik user korábbi személyes/foglalási tartalma nem szolgálható ki cache-ből;
- offline állapotban nem jelenhet meg stale foglalási naptár aktuális adatként;
- biztonságos statikus app-shell/offline fallback cache-elhető;
- új deploy után stale kliens nem ragadhat bent hosszú ideig.

### Technikai irány

Külső PWA plugin helyett egyszerű, saját implementáció:

- Next.js manifest/metadata;
- saját PWA ikonok;
- saját, minimális service worker;
- statikus offline fallback;
- explicit cache-policy;
- a Supabase proxyból kizárt technikai PWA route-ok (`/offline`, `/sw.js`, manifest), mert offline helyzetben ezeknek a session-ellenőrzéstől függetlenül működniük kell.

### Automatikus ellenőrzés

A PWA branch CI-jában a PWA security regressziós teszt, teljes unit test, typecheck és production build PASS állapotot kapott.

### Valós iPhone UAT

A PWA Vercel preview iPhone Safari alatt:

- kezdőképernyőre telepítés: **PASS**;
- standalone indulás: **PASS**;
- offline újraindításkor stale foglalási adat helyett egyértelmű „nincs internet / csak online érhető el” állapot: **PASS**.

A visszatérő hálózat utáni friss adatbetöltés és Android/Chromium PWA UAT még külön ellenőrizendő.

---

## 3. Foglalási e-mail értesítés – új kötelező üzleti követelmény

### A korábbi döntés felülírása

A korábbi projektállapot szerint az automatikus booking confirmation e-mail nem volt go-live blocker. Ezt a 2026-09-03-i tulajdonosi döntés **felülírta**.

Mostantól kötelező:

- minden sikeres új foglalás után e-mail a foglalás tulajdonosának;
- minden sikeres foglalásmódosítás után e-mail a foglalás tulajdonosának;
- minden sikeres törlés/lemondás után e-mail a foglalás tulajdonosának;
- ugyanaz a szabály akkor is, ha a műveletet admin végzi a user helyett;
- e-mail hiba nem fordíthat vissza vagy tehet bizonytalanná egy már sikeres foglalási tranzakciót.

### Ismétlődő foglalás döntés

Egy sorozatos műveletnél **egy összefoglaló e-mail** küldendő, nem külön levél minden előfordulásról.

Példa: 20 alkalmas sorozat létrehozásakor egy levél tartalmazza a sorozat összefoglalását.

### Javasolt technikai minta

Tartós **transactional outbox**:

- a booking create/update/delete adatbázis-tranzakcióval összhangban tartós „e-mail küldendő” esemény keletkezik;
- külön küldő folyamat dolgozza fel;
- sikertelen küldés újrapróbálható;
- küldési státusz és hiba auditálható;
- e-mail szolgáltatási hiba nem okozhat foglalási adatvesztést.

### E-mail szolgáltató irány

A tulajdonos saját domain/tárhely szolgáltatója: **MediaCenter.hu**.

Véglegesített feladó és Reply-To cím: `foglalas@a-hely.com`.

A MediaCenter E-mail Admin alapján igazolt SMTP-adatok:

- host: `pop3.mediacenter.hu` – a szolgáltató szerint nem elírás;
- SSL/TLS port: `465`;
- kötelező hitelesítés, felhasználónévként a teljes `foglalas@a-hely.com` cím;
- a díjmentes SMTP limitje napi 100 levél, levélenként legfeljebb 10 címzett;
- külön privát SMTP hozzáférés vásárolható.

Nyitva marad a privát SMTP limit/ár, valamint az SPF/DKIM/DMARC és bounce-kezelés ellenőrzése. A napi 100-as korlát miatt a díjmentes SMTP csak igazolt terhelési tartalékkal fogadható el productionre.

Jelszó vagy más SMTP secret nem kerülhet chatbe, repositoryba vagy klienskódba.

### GitHub

Issue: **#107 – kötelező foglalási e-mail értesítések**.

### Technikai forrásaudit és döntés – 2026-09-03

A repository és a staging read-only auditja alapján a meglévő `outbox_events` általános outbox nem használható közvetlenül booking e-mail worker forrásaként: sorozatoknál alkalmanként külön eseményt tárol, nincs teljes eseménykori levél-snapshotja, lease/dead-letter/próbálkozásnaplója, és stagingen 135 korábbi, feldolgozatlan eseményt tartalmaz. Ezeket nem szabad utólag automatikusan kiküldeni.

Választott irány: külön `booking_email_outbox`, egy logikai sorozatművelethez egy rekord, verziózott minimális payload, DB-deduplikáció, lease-alapú worker claim, append-only delivery attempt napló, exponenciális retry és dead letter. Az SMTP worker Node.js/Next.js környezetben, provider adapterrel készül; a percenkénti scheduler elsődleges terve Supabase Cron + `pg_net`, environmentenként Vaultban tartott URL/token mellett.

Részletes döntés: `docs/DECISION_2026-09-03_BOOKING_EMAIL_OUTBOX.md`.

### Adatbázis-alapréteg – 2026-09-03

A #111 draft ágon elkészült a külön outbox és append-only kézbesítési napló migrációja, az idempotens belső enqueue helper, valamint a service-role-only lease claim/result RPC. A regressziós csomag 47 pgTAP ellenőrzést és külön két-workeres `SKIP LOCKED` konkurenciatesztet tartalmaz.

Az alkalmazásoldali 91 unit teszt, typecheck és production build PASS. A GitHub Database tests #520 friss resetből 685/685 pgTAP PASS eredményt adott; az új két-workeres outbox claim konkurenciateszt, minden korábbi konkurenciateszt és a schema lint is PASS. A migráció még nincs stagingre alkalmazva. Nem történt valódi e-mail-küldés, main merge vagy production deploy.

### Booking RPC enqueue-integráció – 2026-09-03

A `202609030002_enqueue_booking_emails_from_audit.sql` migráció a kanonikus booking RPC-k meglévő, idempotencia-kulccsal korrelált auditját használja. A `DEFERRABLE INITIALLY DEFERRED` constraint trigger csak a logikai művelet minden booking-, cím- és admin díjazási mellékhatása után készíti el az outbox eseménykori payloadját, de még ugyanabban a tranzakcióban. Egyedi és `occurrence` művelethez egy booking-snapshot, `following`/`series` művelethez egy összefoglaló rekord készül; adminműveletnél is a booking owner a címzett. A payload nem tartalmaz foglalási megjegyzést.

A regressziós csomag további 29 pgTAP ellenőrzést tartalmaz create/update/cancel, admin owner-routing, title utáni snapshot, sorozat create, occurrence/following scope, idempotens retry, rollback és későbbi profil/booking változás elleni immutabilitás lefedésére. A GitHub Database tests #525 friss resetből **714/714 pgTAP PASS** eredményt adott; minden booking-, scope-, hozzáférés- és outbox-konkurenciateszt, valamint a schema lint PASS. Application checks #576 PASS. Staging/production DB alkalmazás, valódi e-mail-küldés, main merge és production deploy nem történt.

### Magyar sablon és provider-szerződés – 2026-09-03

Elkészült a `src/lib/booking-email` providerfüggetlen alkalmazásréteg:

- szigorú, ismeretlen mezőt és verziót elutasító `payload_version=1` parser;
- magyar text és mobilbarát inline-stílusú HTML create/update/cancel sablon;
- `single`, `occurrence`, `following` és `series` megjelenítés;
- admin által végzett művelet jelzése, update előtte/utána blokk és opcionális lemondási ok;
- minden dinamikus HTML-adat escape-elése és CR/LF header-injection tiltása;
- `Europe/Budapest` időzóna és DST-kezelés;
- determinisztikus RFC Message-ID az outbox ID-ból;
- hálózat nélküli capture transport és Nodemailer-kompatibilis kliensadapter;
- SMTP hálózati/4xx retry, auth/5xx dead-letter osztályozás nyers provider válasz továbbadása nélkül.

A helyi teljes csomag 20 fájl / **109 teszt PASS**, TypeScript és Next.js production build PASS. A végleges commiton Application checks #578, Database tests #527 (714/714 pgTAP + minden konkurenciateszt + schema lint) és Vercel PASS. Nodemailer dependency/konfiguráció, worker route, scheduler, SMTP secret és valódi küldés még nem készült; staging/production módosítás nem történt.

### Védett worker és SMTP runtime – 2026-09-03

A #111 draft ágon elkészült a szerveroldali kézbesítési futtató:

- verzióra rögzített Nodemailer `9.1.1` és típuscsomag;
- Node.js `/api/internal/booking-email-worker` Route Handler;
- timing-safe Bearer auth, legalább 32 bájtos `CRON_SECRET` követelménnyel;
- alapértelmezetten biztonságos `BOOKING_EMAIL_MODE=disabled`, amely nem hoz létre DB-klienst és nem claimel;
- explicit `capture` és `send` mód, service-role-only claim/complete RPC adapterrel;
- 10-es alap batch, 300 másodperces lease és a döntési dokumentum szerinti retry ütem;
- payload- és scope-validáció küldés előtt, több címzettet vagy header injectiont lehetővé tevő cím elutasítása;
- nyers SMTP/provider hiba, e-mail tartalom és secret nélküli HTTP-válaszok;
- SMTP-átadás utáni DB completion-hibánál nincs azonnali újraküldés;
- fájl- és URL-beolvasás tiltása a Nodemailer transporton.

A helyi teljes ellenőrzés **22 tesztfájl / 125 teszt PASS**, typecheck és Next.js production build PASS; `pnpm audit --prod` nem talált ismert sérülékenységet. A végleges kódcommiton Application checks #581, Database tests #530 (714/714 pgTAP, minden konkurenciateszt és schema lint), valamint Vercel PASS. A lokális, valódi Route Handler smoke teszt jogosulatlan GET-re 401-et, autorizált `disabled` GET-re 200-at és nulla claim/küldés eredményt adott.

Vercel Cron konfiguráció szándékosan nem került még a repositoryba: az csak production deployon fut, a perces ütem csomagfüggő, miközben az elsődleges architektúraterv továbbra is Supabase Cron + `pg_net`. Scheduler, heartbeat/admin monitor, runtime secret, staging DB-alkalmazás és valós SMTP UAT még nyitott. Main merge vagy production deploy nem történt.

---

## 4. Migráció – üzleti scope és biztonsági irány

Issue: **#108**.

### Migrálandó időszak

A tulajdonosi döntés szerint a migráció **nem teljes történeti migráció**.

Kötelezően átemelendő:

1. a migráció hónapjának **teljes** adatai a hónap első napjától;
2. minden jövőbeli adat/foglalás.

Példa: ha az éles átállás október 15-én történik, akkor október 1-től kezdődő minden szükséges adat/foglalás + minden jövőbeli adat migrálandó.

Ennek oka, hogy a migráció hónapjának havi elszámolása egy rendszerben teljes és visszaellenőrizhető legyen.

### Migrálandó entitások minimuma

- felhasználói alapadatok;
- aktív/inaktív státusz;
- üzletileg szükséges user-beállítások és jogosultságok;
- migráció hónapjának és jövőnek foglalásai;
- ismétlődő sorozatok és szükséges sorozatkapcsolatok;
- szükséges terem/csoport mapping;
- elszámoláshoz szükséges booking attribútumok.

A pontos mezőmapping a forrásrendszer tényleges exportstruktúrája után véglegesíthető.

### Kötelező migrációs módszer

- nem egyszeri kézi DB-beírás;
- scriptelt, újrafuttatható import;
- dry-run mód;
- forrás → cél mezőmapping dokumentáció;
- forrás rekordazonosító / importazonosító a duplikációvédelemhez;
- idempotencia;
- ütközési riport;
- staging próbamigráció;
- forrás/cél rekordszám és üzleti reconciliation;
- production import előtt friss backup;
- végső delta-import az átállási ablakban;
- import után tételes és összesített ellenőrzés;
- visszaállítható rollback/restore terv.

### Még szükséges bemenet

A pontos importáló elkészítéséhez szükséges a jelenlegi AllBooked/Skedda rendszerből egy reprezentatív:

- user export;
- booking export;
- ha külön van: jogosultság/csoport/terem export.

CSV/XLSX exportminta alapján készül a végleges mapping.

---

## 5. Mobil UX – issue #109 / PR #110

### Általános új mobil UI-szabály

A normál menüoldalak mobilon **nem lehetnek oldal-szinten vízszintesen görgethetők**.

- mezők és formok összezsugorodnak a viewporton belül;
- desktop többoszlopos grid-ek mobilon egy oszlopra törnek;
- hosszú szövegek törhetők;
- gombok mobilon megfelelő érintési méretet és szükség esetén teljes szélességet kapnak;
- nagy admin táblák ahol indokolt, kártyás mobilnézetté alakulnak;
- a fő foglalási naptár speciális belső vízszintes szobagörgetése kivétel, az megmarad.

A külön mobil responsive CSS réteg a naptár speciális CSS-étől elkülönítve készült.

### Egységes felső szövegpozíció

Tulajdonosi UI-döntés:

Minden normál mobil oldalon a legfelső `page-heading` szövegblokk az Adataim oldalon elfogadott belső bal pozícióban induljon. A foglalási naptár saját speciális fejlécét ez nem érinti.

### Adataim

Javítva:

- teljes oldal vízszintes overflow;
- fieldset/input/form szélesség;
- felső „Saját profil / Adataim / …” szövegblokk bal oldali behúzása.

Tulajdonosi visszajelzés: **jó**.

### Foglalásaim

Alap reszponzív overflow és form/kártya szabályok alkalmazva. A mobil oldalszintű vízszintes overflow megszüntetése a #109 scope része.

### Felhasználók

A széles desktop `admin-table` mobilon kártyalistává alakul.

Mobil kártyán megmarad:

- név;
- e-mail;
- telefonszám;
- helyiségcsoport;
- ismétlési jog;
- szerepkör;
- állapot;
- teljes szélességű Szerkesztés művelet.

Desktop táblanézet változatlan.

### Havi órák és fizetendő

A három pénzügyi/ellenőrzési tábla mobilon kártyás nézetet kapott:

1. Havi fizetendő;
2. Óra-összesítés;
3. Tételes aktív foglalások.

Minden érték saját mobil címkét kap; pénzügyi mező nem rejtőzik el. A tfoot végösszegek külön kiemelt összesítő blokkban maradnak.

A szűrő és CSV gombok mobilon teljes szélességűek.

#### iOS hónapválasztó regresszió

Az iOS natív `input[type="month"]` vizuálisan túlnyúlt a fieldset jobb szélén. Több CSS-only javítás után is fennmaradt.

Végleges megoldás:

- desktopon a natív hónapmező megmarad;
- mobilon külön **Év + Hónap** select-alapú választó jelenik meg;
- ugyanazt a `YYYY-MM` state-et állítja elő;
- üzleti logika nem változott.

Tulajdonosi iPhone UAT: **PASS („Most jó”)**.

### Díjazás

A Díjazás oldal ugyanazt az `admin-table` osztályt használja, mint a Felhasználók, ezért külön mobil címkézés készült, hogy pénzügyi soron ne jelenjen meg tévesen „E-mail/Telefonszám” stb.

Mobilon:

- Kliens;
- Aktuális mód;
- Ütemezett változások;
- Díjazás editor mezői;
- Érvényes hónap;
- Mentés/Előzmények;
- történeti táblák

kártyás/tördelhető formában jelennek meg.

### Hozzáférések / Közvetlen user-jogok

Mobilon:

- user `details` blokkok teljes szélességűek;
- hosszú név/e-mail törik;
- helyiségjog sorok egy oszlopra törnek;
- checkbox és Mentés gomb jól érinthető;
- oldal-szintű vízszintes overflow nincs.

### Helyiségek / Helyiségcsoportok

Mobilon a Helyiségcsoportok lenyitott szerkesztőrésze kezdetben levágódott.

Ok:

- a desktopból örökölt `.admin-permission-list` `max-height: 32rem; overflow: auto` belső görgetőablaka;
- mobil `details` blokkon `overflow: hidden`.

Javítás:

- mobilon `max-height: none`;
- `overflow: visible`;
- lenyitott csoport teljes szerkesztőrésze és helyiségjog listája lefelé normál oldalgörgetéssel elérhető.

Tulajdonosi iPhone UAT: **PASS („Most jó”)**.

### Beállítások

A Beállítások oldal forrásauditja szerint az előrefoglalási limitek űrlapját a közös mobil responsive réteg már egy oszlopra töri, a mezők és a mentés gomb viewporton belül maradnak. Külön oldal-specifikus javítás nem volt szükséges.

### Lemondások

A hátralévő mobil audit két rést azonosított és javított:

- a széles összesítő és tételes riporttáblák mobilon kártyanézetté alakulnak, az összes üzleti mező saját címkével megmarad;
- a Havi órák oldalon már igazolt iOS `input[type="month"]` megoldással összhangban mobilon külön Év + Hónap választó jelenik meg, desktopon a natív hónapválasztó marad.

Automatikus regresszióvédelem ellenőrzi a kártyanézetet, a kritikus lemondási mezők megtartását és a reszponzív hónapválasztó használatát.

Tulajdonosi iPhone UAT: **PASS („Működik”)**. A külön Év + Hónap választó a kereten belül marad és használható. Valós Android Chrome UAT még szükséges.

### Android

Az általános responsive CSS várhatóan platformfüggetlen, de iOS/Android böngészőeltérések miatt **külön valós Android Chrome UAT szükséges**. iPhone PASS nem tekintendő automatikus Android PASS-nak.

Minimum Android smoke UAT:

- fő naptár vertikális/horizontális scroll + long press;
- Felhasználók;
- Havi órák és fizetendő;
- Díjazás;
- Hozzáférések;
- Helyiségek/Helyiségcsoportok;
- Lemondások, különösen az Év + Hónap választó és a riportkártyák.

### Automatikus tesztek

A mobil responsive layer kapott regressziós tesztet, amely ellenőrzi többek között:

- a külön responsive CSS betöltését;
- page-level overflow védelmet;
- naptár belső scrolljának érintetlenségét;
- többoszlopos admin/form layout mobil összeomlását egy oszlopra;
- külön admin mobil CSS réteg betöltését;
- Díjazás mobil címkézésének jelenlétét.

A releváns PR #110 futásokon unit test, typecheck és production build PASS állapotot kaptak az egyes javítások után.

---

## 6. Inaktív „Mhely” helyiségcsoport törlésének vizsgálata

A tulajdonos jelezte, hogy van egy inaktív `M hely` csoport. A staging adatbázisban a tényleges név `Mhely`.

Vizsgálati eredmény:

- a Helyiségek adminfelület `saveAccessGroup` művelettel létrehozást/módosítást/inaktiválást támogat; külön csoporttörlés UI nincs;
- támogatott `admin_delete_access_group` vagy más csoporttörlő RPC nincs;
- az `access_group_members` és `access_group_rooms` idegen kulcsai `ON DELETE RESTRICT` szabályúak;
- a staging `Mhely` csoport inaktív, jelenleg 0 user-tagsága és 0 room-mappingje van;
- a csoporthoz 2 megőrzött auditbejegyzés tartozik (`created`, `updated`);
- nyers SQL `DELETE` a jelenlegi kapcsolatmentes állapotban fizikailag végrehajtható lenne, de ez nem támogatott, nem auditált admin művelet, ezért nem alkalmazható kerülőútként.

Ajánlott hosszú távú modell:

- alapértelmezett életciklus az inaktiválás;
- külön végleges admin törlés csak akkor készüljön, ha erre explicit üzleti igény van;
- a művelet csak nem kanonikus, már inaktív, aktuális tagság és room-mapping nélküli csoportot törölhessen;
- a dependency-ellenőrzés, zárolás, törlés és `access_group.deleted` audit egy tranzakcióban történjen;
- kapcsolat vagy tiltott kanonikus csoport esetén fail-closed hiba legyen;
- DB-regressziós teszt és független jogosultsági/adatbiztonsági review szükséges.

Az `Mhely` csoportot a vizsgálat során nem töröltük. Az inaktivált állapot működésileg biztonságos; külön törlés funkció készítése tulajdonosi döntésre vár.

---

## 7. Következő fejlesztési sorrend

1. döntés arról, hogy szükséges-e külön, auditált helyiségcsoport-törlés; addig az inaktiválás a támogatott működés;
2. #109 védett oldalak tablet/desktop regressziós ellenőrzése;
3. #109 valós Android Chrome smoke UAT;
4. #110 lezárása csak teljes mobil UAT után;
5. #105 PWA Android/Chromium és network-return UAT;
6. #107 e-mail: a technikai terv elkészült; következő a booking e-mail outbox migráció/RPC tesztimplementációja, majd worker és MediaCenter SMTP paraméterek;
7. #108 migráció: forrásexportok beszerzése, mapping, dry-run importer és staging migráció;
8. külön review/CI/UAT után feature-integráció;
9. `main` merge és production csak explicit tulajdonosi jóváhagyással és a production readiness kapuk lezárása után.

## 8. Release-biztonsági megjegyzés

Ez a dokumentum nem jelent production GO-t. A fenti fejlesztések egy része draft PR/feature branch állapotban van. `main` merge vagy production deploy külön, explicit jóváhagyás nélkül továbbra is tilos.
