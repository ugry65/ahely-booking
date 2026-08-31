# A-Hely production monitoring – UptimeRobot setup

Dátum: 2026-08-31
Kapcsolódó: #100, #102, PR #103
Státusz: ELŐKÉSZÍTVE – production domain/alert cím megadása és külső konfiguráció még szükséges

## 1. Szolgáltató és induló csomag

Induló monitor: UptimeRobot Free.

A 2026-08-31-i hivatalos UptimeRobot információ szerint a Free csomag üzleti/commercial használatra is használható, legfeljebb 50 monitorral és 5 perces alap ellenőrzési intervallummal. Az A-Hely induló monitorcsomagja 6 monitort igényel, ezért a Free keret elegendő.

A 5 perces észlelési idő induláskor elfogadott költség/üzemeltetési kompromisszum. Ha később gyorsabb incident detection szükséges, a fizetős csomag külön döntés.

## 2. Kötelező monitorok

### MON-APP-01 – Production public app

Típus: HTTP(S)
Név: `A-Hely booking – public app`
Cél: a végleges production HTTPS domain kezdő/belépési oldala.
Intervallum: 5 perc.
Elvárás: érvényes HTTP válasz; redirect kezelés a végleges domain/auth működéshez igazítva.

Cél: domain, DNS, TLS/HTTPS, hosting és Next.js elérhetőség külső nézőpontból.

### MON-HEALTH-01 – Application + DB health

Típus: HTTP(S) vagy keyword/API monitor a Free csomag aktuálisan elérhető lehetősége szerint.
Név: `A-Hely booking – app + database health`
Cél: `https://<production-domain>/api/health`
Intervallum: 5 perc.
Elvárt HTTP státusz: 200.
Elvárt tartalom: `"status":"ok"` és `"database":"ok"`.

Az endpoint DB hiba esetén 503-at ad, ezért nem lehet hamis zöld pusztán attól, hogy a Next.js process válaszol.

A publikus válasz nem tartalmazhat secretet, user-adatot, DB hostot, SQL-t vagy stack trace-t.

### MON-BACKUP-08 – 08:00 backup heartbeat

Típus: Heartbeat/Cron.
Név: `A-Hely backup – 08:00`
Várt ping: naponta a 08:00 Europe/Budapest backup sikeres befejezése után.
Grace window: a szolgáltató által támogatott olyan tolerancia, amely figyelembe veszi a GitHub Actions indítási és futási késését; induló célként 60 perc körüli tolerancia javasolt.

### MON-BACKUP-12 – 12:00 backup heartbeat

Típus: Heartbeat/Cron.
Név: `A-Hely backup – 12:00`
Várt ping: naponta a 12:00 Europe/Budapest backup sikeres befejezése után.

### MON-BACKUP-16 – 16:00 backup heartbeat

Típus: Heartbeat/Cron.
Név: `A-Hely backup – 16:00`
Várt ping: naponta a 16:00 Europe/Budapest backup sikeres befejezése után.

### MON-BACKUP-20 – 20:00 backup heartbeat

Típus: Heartbeat/Cron.
Név: `A-Hely backup – 20:00`
Várt ping: naponta a 20:00 Europe/Budapest backup sikeres befejezése után.

Négy külön heartbeat szükséges, mert a 20:00–08:00 közötti szándékos 12 órás szünet miatt egyetlen 4 órás cron-monitor hamis éjszakai riasztást okozna.

## 3. Backup heartbeat biztonsági szabály

A heartbeat URL-t a GitHub `production` environment secretjeiben kell tartani:
- `BACKUP_HEARTBEAT_08_URL`
- `BACKUP_HEARTBEAT_12_URL`
- `BACKUP_HEARTBEAT_16_URL`
- `BACKUP_HEARTBEAT_20_URL`

A backup script csak akkor hívhatja meg a heartbeat URL-t, ha:
1. dump elkészült;
2. belső checksums elkészültek;
3. artifact titkosítása sikerült;
4. Google Drive upload + remote hash verify PASS;
5. B2 upload + remote hash verify PASS.

Részleges backup nem küld success heartbeatet.

## 4. Alert címzett

Production aktiváláshoz szükséges egy ténylegesen figyelt alert e-mail cím. Ezt nem tároljuk repóban.

A minimális alert folyamat:
- DOWN értesítés;
- UP/recovery értesítés;
- az üzemeltető által ténylegesen figyelt csatorna;
- kontrollált drill során bizonyított kézbesítés.

## 5. Kontrollált monitoring drill

Production GO előtt legalább:

1. `MON-APP-01`: kontrollált staging/teszt URL hibával DOWN alert bizonyítása;
2. `MON-HEALTH-01`: DB-health hibás állapotnál 503 és DOWN alert;
3. recovery után UP értesítés;
4. egy backup heartbeat szándékos kihagyása vagy teszt heartbeat monitor timeout → alert;
5. újraindított/sikeres heartbeat után recovery;
6. backup egyik céljának szimulált hibája esetén a pipeline failure és success heartbeat hiányának igazolása.

A production szolgáltatást nem állítjuk le kizárólag drill céljából, ha ugyanez stagingen/kontrollált tesztmódban bizonyítható.

## 6. Opcionális monitorok

Ha a Free csomag aktuális funkciói és a végleges domain lehetővé teszik:
- SSL/domain expiry figyelés;
- lassú válaszidő figyelés;
- külön státuszoldal.

Ezek hasznosak, de nem helyettesítik a fenti 6 kötelező monitort.

## 7. Aktiválási gate

A monitoring csak akkor jelölhető késznek, ha:
- production domain végleges;
- alert címzett jóváhagyott;
- 6 monitor létrejött;
- heartbeat URL-ek GitHub production secretként beállítva;
- health endpoint production/staging környezetben tényleges DB olvasással működik;
- DOWN + recovery drill PASS és dokumentált.

A monitorok konfigurálása önmagában nem production GO.
