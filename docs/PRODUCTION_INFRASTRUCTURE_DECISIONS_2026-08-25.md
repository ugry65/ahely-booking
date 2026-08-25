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

## 5. Következő beszélgetés feladata

A következő chat kizárólag a production infrastruktúra költség/üzembiztonság döntésre fókuszáljon, új üzleti funkció fejlesztése nélkül.

Vizsgálandó:
1. Netlify és más reális hosting alternatívák tényleges kompatibilitása a repository aktuális Next.js 16 architektúrájával.
2. Vercel Pro vs alternatívák teljes költség, kompatibilitás, üzemeltetés, deploy/rollback és kockázat összehasonlítása.
3. Supabase Free + Google Drive saját automatizált backup részletes technikai terve.
4. Backup gyakoriság/RPO, retention, titkosítás, secret-kezelés, monitoring és riasztás.
5. Tényleges restore-próba terve és elfogadási kritériumai.
6. Végső production infrastruktúra ajánlás és go/no-go döntés.

## 6. Változatlan production kapuk

Production deploy továbbra sem történhet addig, amíg:
- teljes CI és kritikus regresszió zöld;
- staging UAT lezárt;
- backup automatizálás működik;
- tényleges restore-próba sikeres;
- kritikus független review megtörtént;
- production konfiguráció és rollback terv ellenőrzött;
- explicit üzleti jóváhagyás nincs.
