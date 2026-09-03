# A-Hely production backup automatizálás – runbook

Dátum: 2026-08-31
Státusz: implementációs baseline; production schedule még NINCS aktiválva.

## 1. Cél

A production PostgreSQL adatbázis rendszeres, kliensoldalon titkosított mentése két független külső célra:

1. Google Drive;
2. Backblaze B2 Object Lock védelemmel.

Elfogadott jövőbeli ütemezés Europe/Budapest szerint: 08:00, 12:00, 16:00, 20:00.

A jelen branch/workflow szándékosan csak kézi `workflow_dispatch` futást tartalmaz. Automatikus production schedule csak sikeres restore-drill, monitoring/alert teszt és explicit production jóváhagyás után kerülhet be.

## 2. Miért natív pg_dump

A backup script közvetlen PostgreSQL `pg_dump`-ot használ, nem kizárólag `supabase db dump` parancsot. Ennek oka, hogy a Supabase CLI menedzselt sémákat (különösen `auth`, `storage`) speciálisan kezeli/kizárja, ezért abból nem következtetünk automatikusan a teljes Auth-visszaállíthatóságra.

A jelen implementáció `pg_dump --format=custom --no-owner --no-privileges --no-subscriptions` archívumot készít. Ez jó alap egy teljes logikai restore-hoz, de **a tényleges Auth-helyreállíthatóság csak restore-drill után tekinthető bizonyítottnak**.

Production kapcsolatnál Supabase esetén közvetlen adatbázis-kapcsolatot vagy Supavisor session mode kapcsolatot kell használni; transaction pooler nem megfelelő pg_dump célra.

## 3. Titkosítás

Valós backup titkosítatlanul nem készülhet. A script kötelezően `age` publikus kulcsos titkosítást használ.

- A backup workflow csak az `AGE_RECIPIENT` publikus recipientet kapja meg.
- A hozzá tartozó private identity kulcs NEM kerül a backup workflow secretjei közé.
- A private kulcs külön restore-secret/offline biztonságos helyen tárolandó.
- Kulcsrotáció előtt bizonyítani kell, hogy a retention alatt lévő régi mentések továbbra is visszafejthetők.

## 4. Mentés formátuma

Egy futás fájljai:

- `<prefix>-<UTC timestamp>-<git sha>.dump.age` – titkosított PostgreSQL dump;
- `.dump.age.sha256` – SHA-256 ellenőrzőösszeg;
- `.manifest.json` – minimális, secretmentes manifest.

A fájlnév minden futásnál új restore-pontot ad; meglévő mentést nem ír felül.

A script lokális plaintext `.dump` fájlt csak átmenetileg hoz létre, 0600 jogosultsággal, majd sikeres titkosítás után azonnal törli. Workflow végén az összes lokális backup artifact és rclone config törlődik.

## 5. Fail-closed feltétel

A futás csak akkor SUCCESS, ha:

1. a dump létrejött és nem üres;
2. az `age` titkosítás sikerült;
3. az SHA-256 és manifest elkészült;
4. a titkosított dump + checksum + manifest felment Google Drive-ra;
5. ugyanaz a három fájl felment Backblaze B2-re;
6. `rclone lsjson --stat` mindkét célon visszaigazolta az objektumok létezését.

Bármely kötelező lépés hibája az egész workflow hibája.

## 6. Google Drive konfiguráció

Az implementáció rclone Drive remote-ot használ saját Google OAuth klienssel. A rclone közös Google client ID-ja 2026-ban kivezetés alatt van, ezért nem használjuk hosszú távú production konfigurációként.

Javasolt scope: `drive.file`, amely az alkalmazás által létrehozott fájlokra korlátozza az írás/olvasás hozzáférést.

Szükséges GitHub Environment secret/variable:

Secrets:
- `BACKUP_GDRIVE_CLIENT_ID`
- `BACKUP_GDRIVE_CLIENT_SECRET`
- `BACKUP_GDRIVE_TOKEN`

Variable:
- `BACKUP_GDRIVE_REMOTE`, pl. `gdrive:A-Hely-Booking-Backups/production`

Az OAuth token létrehozása egyszeri operátori lépés; nem kerül repository-ba.

## 7. Backblaze B2 konfiguráció

A B2 cél külön bucket legyen. Object Lockot és default bucket retentiont külön operátori/admin lépésben kell konfigurálni. **Object Lock bekapcsolása önmagában nem teszi immutable-lá az új fájlokat; default retention is szükséges.**

A backup uploader app key:
- csak a kijelölt bucket/prefixhez férjen hozzá;
- ne kapjon bucket konfiguráció módosítási jogot;
- ne kapjon `bypassGovernance` jogot;
- a default retentiont ne a backup workflow változtassa.

Secrets:
- `BACKUP_B2_KEY_ID`
- `BACKUP_B2_APPLICATION_KEY`

Variable:
- `BACKUP_B2_REMOTE`, pl. `b2:ahely-booking-backups/production`

A governance/compliance mód és a pontos lock/retention időtartam külön jóváhagyandó retention-döntés; ezt az implementáció nem találja ki automatikusan.

## 8. Adatbázis kapcsolat

Secret:
- `BACKUP_DATABASE_URL`

Ez kizárólag a GitHub `production-backup` Environmentben tárolandó, repository fájlban nem.

A workflow PostgreSQL 17 klienssel fut, hogy kompatibilis legyen a jelenlegi Supabase PostgreSQL 17 production projekttel.

## 9. Restore-drill – kötelező production kapu

A mentés csak akkor elfogadható, ha egy külön restore/staging környezetben ténylegesen visszaállítottuk és ellenőriztük.

Minimum ellenőrzés:
- archive SHA-256 egyezik;
- `age` decrypt működik a külön tárolt private identityvel;
- PostgreSQL restore lefut;
- foglalások darabszáma és mintavételes adatai egyeznek;
- user/profile és jogosultsági kapcsolatok konzisztenssek;
- audit adatok megvannak;
- elszámolási adatok konzisztenssek;
- `auth.users` és `auth.identities` visszaállítása ténylegesen bizonyított;
- teszt-login működik;
- Auth Site URL / redirect URL / SMTP és más nem-DB konfiguráció külön checklist alapján helyreállítható;
- ha később Supabase Storage üzleti fájlokat tárol, ahhoz külön objektum-backup szükséges.

## 10. Monitoring kapcsolat

A backup workflow sikere önmagában nem elég. A teljes production monitoringnak ellenőriznie kell, hogy a legutóbbi sikeres backup az elvárt időablakon belül van és mindkét célra eljutott.

Elmaradt vagy részlegesen sikeres mentés automatikus riasztást igényel. Recovery értesítés is szükséges.

## 11. Jelenlegi aktiválási státusz

- backup script: implementálva branch-en;
- secretmentes regressziós teszt: implementálva;
- kézi production-readiness workflow: implementálva;
- production credential: nincs repository-ban;
- automatikus 08/12/16/20 schedule: NINCS aktiválva;
- B2 bucket/Object Lock: operátori konfiguráció szükséges;
- Google OAuth/rclone credential: operátori konfiguráció szükséges;
- `age` private restore identity: külön biztonságos tárolási döntés/operátori setup szükséges;
- tényleges restore-drill: még kötelező;
- független Claude security review: merge előtt kötelező.
