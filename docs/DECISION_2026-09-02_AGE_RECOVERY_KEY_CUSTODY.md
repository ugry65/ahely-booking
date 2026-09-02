# Döntés – age recovery private key megőrzése

Dátum: 2026-09-02
Státusz: **AKTUÁLIS DÖNTÉS**
Kapcsolódó: PR #103, `docs/PRODUCTION_BACKUP_RESTORE_RUNBOOK.md`

## Döntés

A production backupok visszafejtéséhez szükséges `age` recovery private key megőrzésére az A-Hely jelenlegi működési és kockázati szintjén nem követelmény két fizikailag offline USB-adathordozó.

Elfogadott megoldás:

1. egy példány a tulajdonos saját NAS rendszerén;
2. egy második példány egy ettől független másik meghajtón.

A két példánynak külön hibadomént kell képviselnie. Nem számít két független példánynak például:

- ugyanazon NAS két mappája;
- ugyanazon fizikai lemez két partíciója;
- ugyanazon eszköz ugyanazon fájlrendszerén két másolat.

## Tiltott tárolási helyek

A private key továbbra sem kerülhet:

- GitHub repositoryba;
- GitHub Secrets-be;
- a production backup Google Drive mappába;
- a Backblaze B2 production backup bucketbe;
- e-mailbe;
- chatbe;
- képernyőképre vagy más könnyen megosztható dokumentumba.

## Bizonyítás / ellenőrzés

Production-ready állapot előtt elegendő annak igazolása, hogy:

- a NAS-on lévő példány létezik és olvasható;
- a másik független meghajtón lévő példány létezik és olvasható;
- mindkét másolat ugyanahhoz az `age` kulcshoz tartozik, mint amellyel a 2026-09-01-i restore drill sikeresen visszafejtette a production backupot;
- a private key tartalmát az ellenőrzés során nem kell és nem szabad GitHubba, chatbe vagy dokumentációba másolni.

Az ellenőrzéshez fájl-hash vagy az `age` kulcsból származtatott publikus recipient összevetése használható helyben, a private key tartalmának közzététele nélkül.

## Racionálé

A cél a kulcs elvesztésének kockázatát két független példánnyal csökkenteni úgy, hogy a megoldás az A-Hely jelenlegi üzemeltetéséhez arányos és fenntartható maradjon. A két külön hibadomén megtartja a lényegi redundanciát, miközben nem ír elő szükségtelenül bonyolult offline kulcskezelési folyamatot.

## Elsőbbség

Ha a korábbi dokumentáció `két offline példányt` ír elő, ez a 2026-09-02-i döntés az aktuális irányadó követelmény. A runbook következő karbantartásakor ezt a megfogalmazást ehhez a döntéshez kell igazítani.
