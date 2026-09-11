# Production backup schedule – release-readiness

Dátum: 2026-09-11
Scope: issue #101 schedule/monitoring lezárása
Státusz: **kód review-ra kész; production aktiválás tiltott**

## Kiinduló állapot

- `main`: `6acf7f5508a38e0c1ca9c146aace63f8c8a953c2`
- `staging`: `c71f790e20e979898ac38f934ddb243747d008bc`
- PR #103 head: `9edf834858f68900db6e46ae36d5144867789c56`
- A `main` és `staging` jelentősen eltér; ezért a teljes PR #103 átemelése nem biztonságos.
- A `main` production backup drillje már bizonyította a PostgreSQL 17 dumpot, age titkosítást, Google Drive + B2 feltöltést és mindkét cél read-back SHA-256 ellenőrzését.
- A PR #103 review-resolution dokumentuma szerint a korábbi trigger-, OAuth-, nonzero restore-, least-privilege-, concurrency- és Environment-hardening tételek megoldódtak, de a schedule aktiválása és a futó monitoring bizonyítása továbbra is release-gate.

## A tiszta változás tartalma

- Négy GitHub Actions schedule Europe/Budapest időzónával: 08:00, 12:00, 16:00, 20:00.
- A scheduled job alapértelmezetten letiltott. Csak a `PRODUCTION_BACKUP_SCHEDULE_ENABLED=true` production Environment változó explicit, jóváhagyott beállítása aktiválhatja.
- Csak `main` branch engedett; nincs `push` vagy `pull_request` production-secret trigger.
- Kézi futás csak `BACKUP` megerősítéssel.
- Bucket-restricted napi B2 credential; retention/Object Lock admin credential nincs a workflow-ban.
- Külön heartbeat slot minden helyi időpontra.
- `/start` jelzés futáskezdetkor, success kizárólag a két feltöltés és read-back után, `/fail` normál failure/cancellation esetén. Runnerhiba vagy timeout esetén a hiányzó success heartbeat és a monitor grace-idő utáni riasztása a tartalék failure-path.
- Hiányzó vagy nem HTTPS heartbeat URL, ismeretlen cron, hibás branch és részleges feltöltés fail-closed.
- A backup artifact továbbra is roles/schema/data/migration-history + kontrollszámok + manifest + SHA-256, age titkosítással.
- A PostgreSQL 17 kliensbeállítás csak ideiglenes workdirban történik; a repository PostgreSQL 15 baseline-ja nem módosul.

## Időzóna és DST ellenőrzés

A workflow IANA `Europe/Budapest` időzónát használ. Az automatikus teszt igazolja:

- télen 08:00/20:00 helyi idő = 07:00/19:00 UTC;
- nyáron 08:00/20:00 helyi idő = 06:00/18:00 UTC;
- a 2026-03-29-i tavaszi és a 2026-10-25-i őszi óraátállítás napján mind a négy célidő pontosan egyszer következik be.

## Release-gate állapot

| Kapu | Állapot |
|---|---|
| Tiszta, aktuális `main`-alapú branch | PASS |
| Négy Budapest-local schedule | PASS – statikus + DST teszt |
| Csak `main`, nincs PR/push production trigger | PASS – tesztelt |
| Explicit aktiválási kapu | PASS – kód; változó nincs aktiválva |
| Dual-target fail-closed integráció | PASS – mock regressziós teszt; korábbi élő bizonyíték megőrzött |
| Heartbeat start/success/fail | PASS – lokális teszt; élő alert/recovery próba még szükséges |
| Google Drive + B2 secretek és least privilege | korábbi bizonyíték; aktiválás előtt újra ellenőrizendő |
| Zöld CI az új PR head SHA-n | PENDING |
| Független kritikus backup review | első review: CHANGES REQUESTED; javítás utáni re-review PENDING |
| Production schedule aktiválás | BLOCKED – csak explicit jóváhagyással |
| Első négy scheduled futás és heartbeat bizonyíték | BLOCKED – aktiválás után |

## Lokális ellenőrzési bizonyíték

- trigger, heartbeat, schedule/DST, dual-target backup és meglévő drill regressziós tesztek: PASS;
- production DB URL és restore trigger guard regressziók: PASS;
- alkalmazástesztek: 17 fájl / 91 teszt PASS;
- TypeScript typecheck: PASS;
- Next.js production build: PASS;
- added-line credential- és PII-mintakeresés: PASS;
- `git diff --check`: PASS.

A GitHub Actions validáció és a független review eredménye az új PR head SHA-jához kötve külön rögzítendő.

## Kontrollált 08:00 heartbeat failure–recovery drill runbook

A `HEARTBEAT-TEST` a **valós production 08:00 Healthchecks.io monitort** módosítja; nem dummy checket használ. Kizárólag előre bejelentett karbantartási ablakban és a riasztási címzett tudtával futtatható.

Várható hatás:

- a `/fail` ping valós failure-riasztást válthat ki;
- 60 másodperc után a recovery pingnek vissza kell állítania a monitort `Up` állapotba;
- failure- és recovery e-mail érkezhet a konfigurált címzetthez;
- adatbázis-backup, Google Drive/B2 művelet és schedule-aktiválás nem történhet.

Előfeltételek:

1. az aktuális PR head CI-je zöld és független review-ja jóváhagyott;
2. a GitHub `production` Environment védelme csak engedélyezett branchből enged secret-hozzáférést;
3. a Healthchecks felületen a 08:00 monitor a drill előtt `Up`;
4. az operátor rendelkezik Healthchecks-hozzáféréssel és készen áll az azonnali kézi recoveryre.

Végrehajtás és ellenőrzés:

1. a `Production database backup` workflow kézi indításakor a confirmation pontosan `HEARTBEAT-TEST`;
2. ellenőrizni kell, hogy kizárólag a `heartbeat-failure-recovery-test` job futott, a `production-backup` job pedig `skipped`;
3. a futás után a 08:00 monitor legyen `Up`, és a failure/recovery események, valamint az értesítések legyenek dokumentálva;
4. ha a monitor nem áll vissza `Up` állapotba, azonnal küldendő egy normál success ping a Healthchecks felületén megjelenített ping URL-re ellenőrzött kliensből; a URL-t tilos chatbe, ticketbe vagy naplóba másolni;
5. ha a kézi success ping sem állítja helyre, a schedule nem aktiválható, az esetet incidensként kell rögzíteni, és a Healthchecks-konfigurációt ki kell vizsgálni.

## Aktiválási runbook – jelen PR-ban nem végrehajtandó

1. CI legyen zöld az aktuális head SHA-n.
2. Független review blokkoló megállapításai legyenek lezárva ugyanazon vagy újra-review-zott headen.
3. Ellenőrizni kell a négy heartbeat checket és azok grace/alert címzettjeit.
4. Kontrollált alert + recovery tesztet kell végezni személyes adat nélkül.
5. Explicit projektgazdai jóváhagyás után merge a `main` ágba.
6. Külön explicit projektgazdai jóváhagyás után állítható `PRODUCTION_BACKUP_SCHEDULE_ENABLED=true`.
7. Az első 08/12/16/20 ciklus után Drive+B2 artifact/read-back és mind a négy heartbeat bizonyítékát rögzíteni kell.

Production GO addig nem adható, amíg a PENDING/BLOCKED kapuk nincsenek lezárva.
