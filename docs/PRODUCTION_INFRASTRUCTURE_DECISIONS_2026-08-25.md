# A-Hely foglalási rendszer – Production infrastruktúra döntési checkpoint

Dátum: 2026-08-25
Frissítve: 2026-08-31
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

## 3. Supabase production és backup – 2026-08-31-i döntés

A production Supabase célja költségoptimalizálás miatt a **Free plan megtartása**, amennyiben a saját backup/restore és monitoring rendszer production előtt bizonyítottan működik. A Supabase Pro nem kötelező kiindulási feltétel; későbbi upgrade akkor indokolt, ha a Free plan korlátai, rendelkezésre állása vagy az üzemeltetési teher ezt ténylegesen szükségessé teszi.

A Free plan inaktivitás miatti automatikus szüneteltetése külön availability-kockázat. Ezt nem backup-problémaként, hanem monitoring/üzemeltetési kockázatként kezeljük. A production rendszer rendszeres egészségellenőrzése a Supabase/DB működését is ténylegesen ellenőrizze, így a természetes forgalom mellett rendszeres adatbázis-aktivitás is keletkezik. A keep-alive azonban nem helyettesíti a monitoringot és nem tekinthető rendelkezésre állási garanciának.

### 3.1. Véglegesített backup ütemezés

A production PostgreSQL adatbázis automatikus logikai backupja **naponta négyszer**, Europe/Budapest idő szerint:
- 08:00;
- 12:00;
- 16:00;
- 20:00.

Ez tudatos üzleti kompromisszum: nappal legfeljebb kb. 4 órás backup-RPO-t célozunk, éjszaka a 20:00–08:00 közötti hosszabb intervallum elfogadott, mert ebben az időszakban várhatóan kevés módosítás történik. Ha a későbbi tényleges használati adatok jelentős esti/éjszakai aktivitást mutatnak, az ütemezést felül kell vizsgálni.

Minden backup:
- önálló, időbélyegzett visszaállítási pont legyen;
- ne írjon felül korábbi mentést;
- konzisztens PostgreSQL logikai dump legyen;
- tartalmazzon integritás/checksum ellenőrzést;
- sikertelen futás esetén adjon hibajelzést;
- csak akkor számítson sikeresnek, ha a létrehozás és a kijelölt külső célhelyekre történő mentés ellenőrzötten megtörtént.

### 3.2. Két független külső backup cél

Elfogadott célarchitektúra:
1. **Google Drive** – könnyen elérhető off-site backup példány;
2. **Backblaze B2** – szolgáltatói szinten független második off-site példány, Object Lock / törlés elleni védelemmel.

A két cél használatának oka, hogy egyetlen cloud-fiók, szolgáltató, hibás automatizmus vagy véletlen törlés ne veszélyeztesse az összes mentést. A Backblaze B2 elsődleges szerepe a Google Drive-tól független, lehetőség szerint immutable biztonsági példány.

A Dropbox nem elsődleges második backup cél; meglévő fiókként opcionális további példány lehet, de nem helyettesíti a Google Drive + Backblaze B2 két független célarchitektúrát.

### 3.3. Retention és restore

A pontos retention implementáció a backup script készítésekor véglegesítendő, de kötelező:
- többgenerációs megőrzés;
- rövid távon a napon belüli restore-pontok megőrzése;
- hosszabb távú napi és havi restore-pontok;
- a Backblaze B2 oldalon megfelelő Object Lock időtartam;
- dokumentált és lehetőleg scriptelt restore folyamat;
- production indulás előtt tényleges restore-próba külön teszt/staging környezetbe;
- restore után foglalási, jogosultsági, audit- és elszámolási konzisztencia ellenőrzése;
- később rendszeres dokumentált restore-drill.

A backup csak akkor tekinthető megfelelőnek, ha a visszaállíthatóság bizonyított. A két külső másolat megléte önmagában nem elég.

## 4. Hosting / Vercel döntési állapot

A Vercel Hobby/Free production használatát nem tekintjük jelenleg elfogadott megoldásnak az A-Hely üzleti alkalmazásához. A Vercel Pro költsége miatt alternatív hostingot külön vizsgálunk.

Cloudflare Workers korábban már meg lett vizsgálva, és jelenleg BLOKKOLT alternatíva: az alkalmazás Next.js 16 alapú, és a használt proxy.ts / Next.js 16 proxy támogatás kompatibilitása production szempontból nem elfogadható. A Cloudflare irányt addig nem nyitjuk újra, amíg ez a blokkoló kompatibilitási tényező bizonyítottan meg nem oldódik.

Következő külön vizsgálat:
- Netlify kompatibilitás Next.js 16 + proxy.ts + Supabase Auth + Server Actions környezetben;
- szükség esetén további olcsó, üzleti használatra alkalmas Node/Next.js hosting alternatívák;
- Vercel Pro marad a referencia/biztonságos fallback.

Hostingváltás csak proof-of-concept és staging UAT után fogadható el. Productiont a hosting-kísérletek nem érinthetik.

## 5. Production monitoring, health check és proaktív riasztás – kötelező

A monitoring **nem csak a Supabase-re vonatkozik**. Kötelező cél, hogy az A-Hely a teljes production rendszer hibáját vagy súlyos lassulását automatikusan észlelje, és ne a felhasználói hibabejelentésből értesüljön róla.

A health-checknek end-to-end szemléletűnek kell lennie. Minimum ellenőrizendő rétegek:
- **publikus alkalmazás / domain / HTTPS:** a production oldal kívülről elérhető-e;
- **hosting / Next.js alkalmazás:** az alkalmazás ténylegesen képes-e érvényes választ adni;
- **biztonságos health endpoint:** ne csak statikus HTTP 200-at adjon, hanem ellenőrizze az alapvető alkalmazásműködést;
- **Supabase / PostgreSQL:** a backend és az adatbázis elérhető-e, és végrehajtható-e egy biztonságos minimális DB-művelet;
- **válaszidő:** ne csak teljes kiesés, hanem tartós vagy súlyos lassulás is legyen észlelhető;
- **kritikus alkalmazáshibák:** production szerveroldali hibák és indokolt esetben kritikus klienshibák legyenek központilag láthatók;
- **backup pipeline:** a legutóbbi sikeres backup megfelel-e az aktuális 08/12/16/20 ütemezésnek, és mindkét külső célra sikeresen eljutott-e;
- **Google Drive backup cél:** a mentés megléte/eredménye ellenőrizhető legyen;
- **Backblaze B2 backup cél:** a mentés megléte és védettsége ellenőrizhető legyen;
- **SSL/domain lejárat:** lehetőség szerint előre jelezze a lejárati problémát.

### 5.1. Független külső monitor

Az elsődleges uptime/health monitor lehetőség szerint **ne ugyanazon a hosting infrastruktúrán fusson**, mint maga az alkalmazás. Közös hosting-kiesés esetén is képesnek kell lennie hibát észlelni és riasztani.

A monitoring rendszeres időközönként fusson. A pontos szolgáltató és intervallum külön production readiness döntés, elsődleges szempont az ingyenes vagy nagyon alacsony költség, megfelelő megbízhatóság mellett.

### 5.2. Riasztás és recovery

Automatikus riasztás szükséges legalább:
- production elérhetetlenség;
- ismételt health-check hiba;
- Supabase/DB hiba;
- súlyos vagy tartós válaszidő-romlás;
- kritikus alkalmazáshiba;
- elmaradt vagy sikertelen backup;
- ha a backup egyik célhelyre nem jutott el.

A rendszer helyreállásáról **recovery értesítés** is szükséges.

A publikus health endpoint nem adhat ki secretet, user-adatot, belső adatbázis-információt vagy részletes stack trace-t. A mélyebb diagnosztika védett logban/monitoring csatornán maradjon.

### 5.3. Monitoring elfogadási teszt

Production indulás előtt kontrollált teszttel bizonyítani kell, hogy a monitoring valóban működik. Legalább:
- stagingen vagy kontrollált környezetben hibás health választ / kiesést előidézni;
- bizonyítani, hogy a külső monitor észleli;
- bizonyítani, hogy a riasztás ténylegesen megérkezik;
- helyreállítás után a recovery jelzés megérkezik;
- backup heartbeat hibát szimulálni és ellenőrizni a riasztást;
- ahol biztonságosan megoldható, külön DB/Supabase hibát is megkülönböztetni az alkalmazás/hosting hibától.

## 6. Következő production infrastruktúra feladatok

1. A Google Drive + Backblaze B2 backup automatizálás technikai megtervezése és implementálása.
2. A 08:00 / 12:00 / 16:00 / 20:00 Europe/Budapest ütemezés kialakítása.
3. Retention, titkosítás, checksum, secret-kezelés és B2 Object Lock pontos beállításának véglegesítése.
4. Tényleges restore-próba terve, végrehajtása és elfogadási kritériumainak dokumentálása.
5. Teljes production health-check/monitoring szolgáltató kiválasztása költség és megbízhatóság alapján.
6. Health endpoint és backup heartbeat implementálása.
7. Riasztási és recovery csatorna kialakítása és kontrollált tesztje.
8. Hosting véglegesítése és teljes production go/no-go ellenőrzés.

## 7. Változatlan production kapuk

Production deploy továbbra sem történhet addig, amíg:
- teljes CI és kritikus regresszió zöld;
- staging UAT lezárt;
- backup automatizálás működik a jóváhagyott napi négyszeri ütemezéssel;
- Google Drive + Backblaze B2 külső mentés bizonyított;
- tényleges restore-próba sikeres;
- teljes production monitoring/health-check és riasztás működése kontrollált teszttel bizonyított;
- kritikus független review megtörtént;
- production konfiguráció és rollback terv ellenőrzött;
- explicit üzleti jóváhagyás nincs.
