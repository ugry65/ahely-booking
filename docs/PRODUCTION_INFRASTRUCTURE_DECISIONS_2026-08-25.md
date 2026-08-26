# A-Hely foglalási rendszer – Production infrastruktúra döntési checkpoint

Dátum: 2026-08-25
Státusz: a funkcionális fejlesztési fázis lezárása után, production readiness előtt.

## 1. Lezárt funkcionális scope

A staging UAT alapján működik és elfogadott:
- sávos / progresszív / Free díjazás;
- díjazási érvényességi időszakok;
- Tréningterem csoportos foglalás default 5 000 Ft/óra;
- admin a Tréningterem csoportos díját foglalásonként felülírhatja;
- Havi órák / fizetendő összesítés;
- tételes aktív foglalásokban a Foglalás címe;
- részletes CSV exportban a Foglalás címe.

A Befizetések UI NEM része az aktív foglaló rendszer scope-jának. A befizetés rögzítése a külön pénzügyi elszámolási folyamat része; ott a Skedda/elszámolási agent könyveli a befizetési információt. A korábban létrehozott payment DB-réteget nem töröltük vissza, de az alkalmazás UI-jából és navigációjából kivettük, a közvetlen oldal pedig nem használható aktív funkcióként.

## 2. Production review során elvégzett hardening

Production blocker került azonosításra a Tréningterem egyedi admin díjánál: a foglalás létrehozása és az egyedi díj korábban két külön DB művelet volt. Ez félkész állapotot okozhatott volna, ha a foglalás sikerül, a díjrögzítés viszont nem.

Javítás: tranzakciós admin wrapper készült egyedi foglalásra és ismétlődő sorozatra. A foglalás/sorozat és az egyedi csoportos díj egy PostgreSQL tranzakcióban történik; hiba esetén minden visszagördül. Rollback regressziós teszt készült.

Security hardening:
- a belső booking-title request helper közvetlen authenticated API-hívása lezárva;
- fizikai törlést/audit módosítást tiltó trigger helper függvények fix search_path-ot kaptak;
- settlement snapshot/revision immutabilitás review során nem találtunk új production blockert.

## 3. Supabase production költség és backup döntési irány

A production Supabase jelenlegi terve: elsődlegesen vizsgáljuk a Free plan megtartását költségoptimalizálás miatt.

A Free plan elfogadásának feltétele, hogy saját, automatizált és ellenőrzött backup/restore rendszert építsünk. A projekt adatbiztonsági elve nem változik: foglalási vagy elszámolási adat elvesztése elfogadhatatlan.

Tervezett saját backup irány:
- rendszeres automatikus PostgreSQL logikai backup, nem csak manuális mentés;
- célként napi egynél gyakoribb mentés vizsgálandó (pl. 4–6 órás RPO);
- off-platform tárolás;
- Google Drive elfogadható jelölt off-site backup tárhelyként;
- több generáció megőrzése (javasolt legalább 30 napi verzió + hosszabb havi archiválás);
- backup integritás/checksum és futási eredmény ellenőrzése;
- sikertelen backup esetén riasztás;
- dokumentált és lehetőleg scriptelt restore folyamat;
- production indulás előtt kötelező tényleges restore-próba külön teszt/staging környezetbe;
- restore után foglalási, jogosultsági, audit- és pénzügyi konzisztencia ellenőrzése.

A Supabase Pro továbbra is lehetséges későbbi upgrade, ha a Free plan limitek, rendelkezésre állás vagy az üzemeltetési teher indokolja. Jelenleg azonban nem tekintjük automatikusan kötelező production feltételnek; előbb a saját backup megoldást tervezzük és bizonyítjuk.

## 4. Hosting / Vercel döntési állapot

A Vercel Hobby/Free production használatát nem tekintjük jelenleg elfogadott megoldásnak az A-Hely üzleti alkalmazásához. A Vercel Pro költsége miatt alternatív hostingot külön vizsgálunk.

Cloudflare Workers korábban már meg lett vizsgálva, és jelenleg BLOKKOLT alternatíva: az alkalmazás Next.js 16 alapú, és a használt proxy.ts / Next.js 16 proxy támogatás kompatibilitása production szempontból nem elfogadható. A Cloudflare irányt addig nem nyitjuk újra, amíg ez a blokkoló kompatibilitási tényező bizonyítottan meg nem oldódik.

Következő külön vizsgálat:
- Netlify kompatibilitás Next.js 16 + proxy.ts + Supabase Auth + Server Actions környezetben;
- szükség esetén további olcsó, üzleti használatra alkalmas Node/Next.js hosting alternatívák;
- Vercel Pro marad a referencia/biztonságos fallback.

Hostingváltás csak proof-of-concept és staging UAT után fogadható el. Productiont a hosting-kísérletek nem érinthetik.

## 5. Production monitoring, heartbeat és proaktív riasztás

Új kötelező production követelmény: az A-Hely ne a felhasználói hibabejelentésből értesüljön arról, hogy a foglalási rendszer nem működik vagy súlyosan lelassult.

A production infrastruktúra véglegesítésekor külön monitoring és riasztási megoldást kell tervezni és bevezetni.

Minimum elvárt monitoring rétegek:
- **külső uptime/heartbeat ellenőrzés:** független szolgáltatás rendszeres időközönként kívülről ellenőrizze a production alkalmazást;
- **alkalmazás health endpoint:** legyen olyan biztonságos health-check végpont, amely nem csak azt bizonyítja, hogy a webserver HTTP választ ad, hanem ellenőrizni tudja az alkalmazás alapvető működőképességét;
- **adatbázis/Supabase elérhetőség ellenőrzése:** a health-check különbséget tudjon tenni frontend/hosting és backend/adatbázis hiba között, érzékeny adat kiadása nélkül;
- **válaszidő figyelés:** ne csak teljes leállás, hanem tartós vagy súlyos lassulás is észlelhető legyen;
- **hibaarány / alkalmazáshibák figyelése:** production szerveroldali hibák és kritikus klienshibák lehetőség szerint központilag láthatók legyenek;
- **backup heartbeat:** külön ellenőrizni kell, hogy a legutóbbi sikeres backup nem régebbi-e a megengedett RPO-nál; a backup script futása önmagában nem elegendő;
- **riasztás:** kiesés, ismételt health-check hiba, kritikus lassulás vagy elmaradt backup esetén az admin proaktív értesítést kapjon megfelelő csatornán;
- **recovery értesítés:** a rendszer helyreállásáról is legyen jelzés, hogy az incidens lezárható legyen;
- **monitoring függetlenség:** az elsődleges uptime monitor lehetőség szerint ne ugyanazon hosting infrastruktúrán fusson, mint maga az alkalmazás, mert közös kiesés esetén nem tudna riasztani.

A health endpoint nem tartalmazhat érzékeny adatot, secretet, user-információt vagy részletes belső hibát publikus válaszban. A monitoringhoz szükséges mélyebb diagnosztika külön védett/logging csatornán történjen.

A végleges megoldás kiválasztásakor vizsgálandó:
- ingyenes vagy nagyon alacsony költségű uptime-monitor szolgáltatások;
- ellenőrzési gyakoriság és várható észlelési idő;
- e-mail/push/egyéb riasztási lehetőség;
- response-time és SSL/domain expiry monitoring;
- alkalmazás- és error-monitoring külön szolgáltatásának szükségessége;
- a hosting szolgáltató saját monitoringjának használhatósága második jelként, de nem kizárólagos ellenőrzésként;
- false positive riasztások kezelése és incidens-eszkaláció.

Production readiness során konkrét monitoring elfogadási tesztet kell végrehajtani: kontrolláltan hibás health választ vagy staging kiesést kell előidézni, és bizonyítani kell, hogy a külső monitor ezt észleli és a riasztás ténylegesen megérkezik. A recovery jelzést is ellenőrizni kell.

A monitoring végleges szolgáltatója és pontos intervalluma még nyitott production infrastruktúra-döntés; a **proaktív működésfigyelés követelménye azonban ettől kezdve kötelező**.

## 6. Következő beszélgetés feladata

A következő chat kizárólag a production infrastruktúra költség/üzembiztonság döntésre fókuszáljon, új üzleti funkció fejlesztése nélkül.

Vizsgálandó:
1. Netlify és más reális hosting alternatívák tényleges kompatibilitása a repository aktuális Next.js 16 architektúrájával.
2. Vercel Pro vs alternatívák teljes költség, kompatibilitás, üzemeltetés, deploy/rollback és kockázat összehasonlítása.
3. Supabase Free + Google Drive saját automatizált backup részletes technikai terve.
4. Backup gyakoriság/RPO, retention, titkosítás, secret-kezelés, monitoring és riasztás.
5. Tényleges restore-próba terve és elfogadási kritériumai.
6. Production uptime/heartbeat, health-check, válaszidő- és hibamonitoring, valamint proaktív riasztás konkrét megoldásának kiválasztása és tesztelése.
7. Végső production infrastruktúra ajánlás és go/no-go döntés.

## 7. Változatlan production kapuk

Production deploy továbbra sem történhet addig, amíg:
- teljes CI és kritikus regresszió zöld;
- staging UAT lezárt;
- backup automatizálás működik;
- tényleges restore-próba sikeres;
- production monitoring/heartbeat és riasztás működése kontrollált teszttel bizonyított;
- kritikus független review megtörtént;
- production konfiguráció és rollback terv ellenőrzött;
- explicit üzleti jóváhagyás nincs.
