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

Preferált feladó: saját A-Hely domainhez tartozó külön postafiók, például `foglalas@a-hely.com`.

A MediaCenter SMTP használata megvizsgálandó/konfigurálandó. Szükséges technikai adatok:

- SMTP host;
- port;
- TLS/STARTTLS/SMTPS mód;
- felhasználónév;
- alkalmazásjelszó/jelszó biztonságos secretként;
- küldési limitek;
- SPF/DKIM/DMARC ellenőrzés.

Jelszó vagy más SMTP secret nem kerülhet chatbe, repositoryba vagy klienskódba.

### GitHub

Issue: **#107 – kötelező foglalási e-mail értesítések**.

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
6. #107 e-mail: MediaCenter SMTP paraméterek + outbox technikai terv/implementáció + tesztek;
7. #108 migráció: forrásexportok beszerzése, mapping, dry-run importer és staging migráció;
8. külön review/CI/UAT után feature-integráció;
9. `main` merge és production csak explicit tulajdonosi jóváhagyással és a production readiness kapuk lezárása után.

## 8. Release-biztonsági megjegyzés

Ez a dokumentum nem jelent production GO-t. A fenti fejlesztések egy része draft PR/feature branch állapotban van. `main` merge vagy production deploy külön, explicit jóváhagyás nélkül továbbra is tilos.
