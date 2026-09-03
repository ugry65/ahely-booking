# A-Hely foglalási rendszer – Backup restore runbook

Dátum: 2026-08-31
Kapcsolódó: #100, #101
Státusz: DRAFT – kizárólag staging/sandbox restore drillhez

> **TILOS** ezt a runbookot közvetlenül production adatbázisra futtatni külön release/incident döntés és explicit jóváhagyás nélkül.

## 1. Cél

Bizonyítani, hogy a Google Drive + Backblaze B2 helyen tárolt, kliensoldalon titkosított backup artifactból az A-Hely adatbázisa és az elszámolás szempontjából kritikus történeti adatok izolált környezetbe visszaállíthatók.

A restore drill nem csak technikai `psql` siker. A visszaállítás után kötelező a foglalási, jogosultsági, audit-, díjazási és settlement konzisztencia ellenőrzése.

## 2. Előfeltételek

- külön, törölhető Supabase staging/sandbox projekt;
- a sandbox Postgres főverziója kompatibilis a source projekttel;
- `psql` telepítve;
- a backup készítésével kompatibilis Supabase CLI telepítve;
- `age` telepítve;
- `sha256sum`, `tar` elérhető;
- a kiválasztott backup titkosított artifactja és `.sha256` sidecarja letöltve;
- a recovery `age` private key elérhető az erre jogosult személy számára;
- a target DB URL secretként átadva, nem shell historyba vagy dokumentumba beírva.

## 3. Backup azonosítása

Jegyzőkönyvben rögzíteni kell:
- source: Google Drive vagy Backblaze B2;
- artifact pontos neve;
- artifact UTC timestampje;
- artifact SHA-256;
- source Git commit SHA a manifestből;
- restore target Supabase project ref;
- restore kezdete és befejezése;
- végrehajtó/reviewer.

## 4. Külső artifact integritásellenőrzése

A letöltött artifact és sidecar legyen ugyanabban a könyvtárban.

```bash
sha256sum --check ahely-booking-production_*.tar.gz.age.sha256
```

Bármilyen checksum eltérés esetén STOP. Másik backup példányt kell választani vagy a két külső célhely eltérését kivizsgálni.

## 5. Visszafejtés

A private key-t ne másoljuk a repóba és ne írjuk parancssori argumentumba, ha az shell historyba kerülhet.

Példa environment/file alapú biztonságos használatra:

```bash
age --decrypt \
  --identity "$AGE_IDENTITY_FILE" \
  --output restore.tar.gz \
  ahely-booking-production_*.tar.gz.age
```

A decrypted bundle csak ideiglenes, kontrollált munkakönyvtárban létezzen, minimum szükséges ideig.

## 6. Bundle ellenőrzése

```bash
mkdir restore-payload
tar -xzf restore.tar.gz -C restore-payload
cd restore-payload
sha256sum --check SHA256SUMS
```

Kötelező fájlok:
- `roles.sql`
- `schema.sql`
- `data.sql`
- `migration-history.sql`
- `manifest.json`
- `DATA_SHA256SUMS`
- `SHA256SUMS`

Checksum hiba esetén STOP.

## 7. Target biztonsági ellenőrzés

A restore script/parancsok előtt kötelező bizonyítani, hogy a target NEM production.

Minimum:
- target project ref nem egyezhet a production ref-fel;
- target DB hostname/ref kerüljön kiírásra maszkolt formában;
- külön `RESTORE_CONFIRMATION=SANDBOX` vagy hasonló explicit guard legyen.

Automatizált restore script készítésekor a production project ref explicit denylist/guard legyen.

## 8. Restore sorrend

A Supabase hivatalos migrációs irányával összhangban a logikai restore sorrendje:

1. roles;
2. schema;
3. data;
4. migration history;
5. szükséges auth/storage custom schema változások, ha vannak;
6. platform-szintű konfigurációk külön helyreállítása.

Példa:

```bash
psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file roles.sql \
  --dbname "$RESTORE_DB_URL"

psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file schema.sql \
  --dbname "$RESTORE_DB_URL"

psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file data.sql \
  --dbname "$RESTORE_DB_URL"

psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file migration-history.sql \
  --dbname "$RESTORE_DB_URL"
```

A tényleges restore drill előtt ezt a sorrendet sandboxon ellenőrizni kell, mert a Supabase managed target projekt már rendelkezik platform-managed auth/storage objektumokkal. Ha a schema restore ilyen objektummal ütközik, nem improvizálunk production közeli környezetben: a restore eljárást külön javítjuk és újrateszteljük.

## 9. Auth helyreállítás

A `auth.users` és kapcsolódó auth-adatok az adatbázis részei, ezért a restore elfogadásának kötelező eleme a felhasználók megőrzésének bizonyítása.

Külön ellenőrizendő:
- `auth.users` rekordok;
- `auth.identities`, ha releváns;
- `public.profiles.id` ↔ `auth.users.id` kapcsolatok;
- aktív/inaktív profilok;
- admin szerepkörök.

Fontos platform-szintű különbségek:
- JWT/API secret és kulcsok target projekten eltérhetnek;
- meglévő sessionök emiatt érvénytelenné válhatnak;
- Auth redirect URL-eket és provider konfigurációt külön kell beállítani;
- encryption root key szükségességét a választott restore célfolyamat szerint külön kell kezelni.

A napi backup artifact nem tartalmazza a recovery secret kulcsokat.

## 10. Storage

A jelenlegi MVP repo nem használ Supabase Storage API-t. Emiatt a 2026-08-31-i restore drillben nincs Storage object binary restore.

Ha később Storage használat kerül a rendszerbe, a database restore önmagában NEM elég: külön objektum-backup/restore komponens kötelező.

## 11. Adatkonzisztencia ellenőrzés

A restore után legalább az alábbiakat kell összevetni a source backup előtti kontrollszámokkal vagy a manifest/jegyzőkönyvben rögzített értékekkel.

### 11.1. Auth / profil
- auth user count;
- profile count;
- orphan profile count = 0;
- aktív adminok száma ésszerű és nem 0.

### 11.2. Foglalás
- összes booking count;
- active/cancelled/admin-deleted státusz bontás;
- booking series count;
- recurrence exception count;
- booking ↔ room és booking ↔ user FK konzisztencia;
- nincs váratlan fizikai adatvesztés.

### 11.3. Jogosultság
- room count;
- user-room permission count;
- aktív user számára a korábbi jogosultságok visszaálltak.

### 11.4. Audit
- audit log count;
- kritikus booking/admin műveletek audit sora megvan;
- audit immutabilitási trigger/funkció jelen van.

### 11.5. Díjazás és settlement
- pricing configuration count;
- effective periodok;
- booking-specific Training room rate adatok;
- settlement snapshot count;
- settlement revision count;
- snapshot/revision immutabilitás regresszió PASS.

## 12. Automatikus regresszió

A restore célon futtatni kell a kritikus DB teszteket vagy egy külön restore-verification tesztcsomagot. Minimum:
- normál booking;
- overlap tiltás;
- konkurens dupla foglalás védelem;
- jogosultság;
- cancellation/update cutoff;
- pricing;
- audit;
- settlement immutabilitás.

A tesztek nem módosíthatják véglegesen a restore verificationhez szükséges mintát; tranzakció/rollback vagy külön ellenőrző sandbox használata szükséges.

## 13. Restore PASS definíció

Restore drill csak akkor PASS, ha:
- külső és belső checksum PASS;
- restore hiba nélkül lefut;
- auth/profile konzisztencia PASS;
- booking és recurring adatok PASS;
- permission PASS;
- audit PASS;
- pricing/settlement PASS;
- kritikus regresszió PASS;
- a jegyzőkönyv minden szükséges SHA/timestamp/target bizonyítékot tartalmaz.

Bármelyik kritikus eltérés = FAIL, production gate zárva marad.

## 14. Biztonságos takarítás

Sikeres vagy sikertelen drill után:
- decrypted SQL/bundle lokális példányok biztonságosan törlendők a kontrollált runnerből;
- private recovery key nem maradhat CI runneren;
- sandbox projekt törlése csak a jegyzőkönyv és review után történhet;
- a forrás backup a GDrive/B2 célhelyen változatlan marad.

## 15. Production incident restore

Production visszaállítás külön incident/change folyamat. Legalább:
- friss eseményértékelés;
- adatírás befagyasztásának szükségessége;
- legjobb restore-pont kiválasztása;
- RPO/adatvesztési ablak explicit értékelése;
- legalább két személyes/független review a kritikus lépésekre;
- explicit `PRODUCTION` jóváhagyás;
- restore utáni teljes konzisztencia- és üzleti ellenőrzés.

A sandbox runbook sikeres bizonyítása előfeltétele annak, hogy production incident restore terv egyáltalán elfogadható legyen.
