# A-Hely saját foglalási rendszer – projektkontextus

## Cél
Az A-Hely jelenlegi AllBooked/Skedda rendszerének kiváltása saját, webalapú foglalási és elszámolási rendszerrel. A rendszer legyen egyszerű, mobilon is jól használható, biztonságos, auditálható, és kezelje a havi elszámolást is.

## Szerepkörök
**Admin:** userek, helyiségek, jogosultságok, árak, foglalási szabályok, foglalások, elszámolás, befizetések, export és beállítások kezelése.

**Normál user:** csak az engedélyezett helyiségeket és foglalásokat látja; foglalhat, saját foglalását szabály szerint módosíthatja/törölheti; ismétlődő foglalás csak engedélyezett keretek között. A havi elszámolási dashboard userenként ki- és bekapcsolható. Más userek neve alapból látható, de admin userenként letilthatja.

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
- Csoportos használat: külön admin által állítható díj, jelenlegi default 5000 Ft/óra.

## Lemondás
- Normál user 24 órán belül már nem törölhet.
- Admin bármikor törölhet.
- Admin által törölt foglalás nem kerül az elszámolásba.
- A törlésről auditrekord marad.
- Havi statisztika: törölt foglalások száma és a törlés előtti idő; részletes lista is lekérhető.

## Díjazás
Default havi sávos díjazás a teljes havi elszámolandó normál óraszám alapján:
- 1–15 óra: 2700 Ft/óra
- 16–60 óra: 1900 Ft/óra
- 61 órától: 1700 Ft/óra

Admin userenként egyedi fix óradíjat is beállíthat, amely felülírja a default sávos díjazást.

A normál szobák díjazása ugyanaz; kivétel a Tréningterem csoportos használata.

## Havi user dashboard
Userenként kapcsolható. Mutassa:
- havi foglalások számát;
- havi óraszámot;
- aktuális/becsült fizetendőt;
- lezajlott és hátralévő órákat;
- havi részletes foglalási listát.

A sávos díj miatt a hónap közbeni fizetendő összeg változhat.

## Elszámolás
A foglalórendszer legyen az elsődleges havi elszámolási nyilvántartás.

User/hónap szinten:
- óraszám;
- óradíj;
- fizetendő;
- befizetett;
- fennmaradó;
- fizetési státusz;
- számlás / számla nélküli;
- fizetés módja: készpénz / utalás;
- pénz célhelye: Privát OTP / Teem Kft. OTP / Pénztár;
- admin megjegyzés / korrekció indoka.

Státuszok: Fizetendő, Részben fizetve, Fizetve, Nem fizetendő/korrekció.
A „Fizetve” státuszt admin kezeli.
Nincs kötelező havi lezárás; utólagos módosítás admin által lehetséges, kötelező indoklással és auditnaplóval.

## Excel export
MVP-ben kötelező XLSX export a pénzügyi dashboardhoz.

Jelenlegi fejlécminta:
- Holder Last name
- Óra
- Óradíj
- Összeg
- Szja
- Számla kérve
- Fizetve
- Számla sorszám

A számla sorszáma az MVP-ben nem kötelező, de opcionális mezőként legyen az adatmodellben. Később számlázó-rendszer export/import alapján automatikusan hozzárendelhető.

Az export mezői később konfigurálhatók legyenek.

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
- napi automatikus backup;
- visszaállíthatóság;
- adatbázis-tranzakciók;
- adatbázis-szintű ütközésvédelem;
- backend jogosultságellenőrzés;
- auditnapló;
- technikai hibalog.

Adatmegőrzési cél: 2 év.
A tervezett törlés előtt admin figyelmeztetés: 30 / 15 / 5 / 1 nappal.
Automatikus végleges törlés helyett admin jóváhagyása szükséges.

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

A végleges technikai architektúrát a fejlesztés elején rögzíteni kell.

## Fejlesztési munkamód
1. FS
2. Technikai architektúra
3. Adatmodell
4. GitHub repository és issue-k
5. Implementáció
6. Automatikus tesztek
7. Független AI/Claude review
8. Javítás
9. Üzleti specifikáció szerinti ellenőrzés
10. Staging
11. Élesítés

Különösen szigorú review kell a foglalási motorra, ütközésvédelemre, jogosultságokra, sávos díjszámításra, elszámolásra, backupra és restore-ra.

## Első fejlesztési prioritás
1. Projekt inicializálása
2. Adatmodell
3. Auth és jogosultság
4. Helyiségkezelés
5. Foglalási motor
6. Ütközésvédelem
7. Ismétlődő foglalások
8. Lemondási szabályok
9. Díjszámítás
10. Havi elszámolás
11. Admin/user UI
12. XLSX export
13. Backup és audit
14. Automatikus tesztek

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

A backup és restore követelmény nem enyhül: tényleges backup és sikeres restore-drill nélkül production indulás nem megengedett. A teljes pénzügyi modul továbbra is későbbi fázis.

A funkcionális UAT részletes, verziózott forrása: `docs/FUNKCIONALIS_UAT_CHECKLIST.md`.

## 2026-08-20-i foglalási UI/UX baseline döntés

A staging UAT és a Skedda mobil/desktop összehasonlítás alapján a már kialakított foglalási UX **regresszióvédett projektkövetelménnyé** vált.

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

Nyitott, még nem lezárt UX tételek külön vannak jelölve ebben a baseline-ban; ezek fejlesztése nem ad felhatalmazást a már elfogadott elemek eltávolítására.

## Nem MVP
- bankkártyás fizetés
- SSO/SAML
- membership
- discount codes
- floor plan
- add-ons
- natív mobilapp
- komplex notification engine
- közvetlen számlázó-integráció
- teljes statisztikai dashboard

## Új fejlesztési beszélgetés indítása
Az új fejlesztési beszélgetés első feladata:
1. ezt a projektkontextust és az aktuális FS-t áttekinteni;
2. foglalási/UI feladat esetén kötelezően áttekinteni a `docs/BOOKING_UI_UX_BASELINE.md` és `docs/skedda-mobile-calendar-ux.md` fájlokat;
3. az aktuális technikai architektúra- és adatmodelldokumentumot áttekinteni;
4. a GitHub `main` branch aktuális állapotát tekinteni a forráskód hiteles forrásának;
5. új fejlesztés előtt ellenőrizni, hogy az nem okoz-e regressziót a baseline-ban rögzített működésben.

Ez a fájl legyen a projekt tartós kontextusfájlja, és a fejlesztés során verziózni kell.
