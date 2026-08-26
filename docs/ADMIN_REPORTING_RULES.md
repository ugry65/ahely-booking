# Admin riportok – elszámolás és lemondások

Dátum: 2026-08-22; frissítve: 2026-08-26

Ez a dokumentum az A-Hely admin riportjainak elfogadott üzleti szabályait rögzíti.

## Havi órák – számlázási / elszámolási alap

- A havi órák riport kizárólag `active` státuszú, le nem mondott foglalásokat tartalmazhat.
- `cancelled` foglalás sem az összesített óraszámba, sem a tételes elszámolási listába nem kerülhet.
- A hónaphatárok és a dátumok `Europe/Budapest` időzónában értendők.
- Egy vagy több, egymástól független elszámolási hónap választható ki egyszerre.
- Több hónap kiválasztásakor az adatok nem olvadhatnak össze: a hónap külön dimenzió/oszlop marad az összesítőben és az exportban.
- Az összesítő admin nézet hónaponként és userenként a felhasználó nevét és az összes foglalt órát mutatja.
- A foglalások darabszáma és az összes perc nem része az üzleti összesítőnek.
- Az összesítő CSV legalább: `Hónap`, `Felhasználó`, `Összes óra`.
- Az óraszám CSV-ben magyar decimális vesszővel kerül kiadásra, hogy a magyar Excel ne dátumként értelmezze például a `4.50` értéket.
- Admin ellenőrzéshez ugyanazokra a kijelölt hónapokra tételes aktív foglalási lista kérhető le összes userre vagy egy kiválasztott userre.
- A tételes aktív lista legalább: hónap, user, dátum, helyiség, kezdés, befejezés, óraszám, **Foglalás címe**.
- A `Foglalás címe` különösen Tréningterem admin foglalásnál üzletileg fontos, mert ebből azonosítható, hogy kinek/milyen csoportnak történt a foglalás.
- A tételes aktív foglalási listához külön CSV export kötelező, amely a `Foglalás címe` mezőt is tartalmazza.
- Ha bármely kiválasztott hónap lekérdezése hibázik, hiányos összesítő vagy részletes CSV nem készülhet; a hiba legyen egyértelmű.

## Lemondások – külön admin monitoring

A lemondási riport nem része a számlázási / elszámolási havi órák riportnak.

- Választható időszak: 1, 3, 6 vagy 12 hónap.
- A vizsgált időszak a foglalás eredeti, `Europe/Budapest` szerinti kezdési dátuma alapján értendő.
- Userenként látható az összes eredeti foglalás, az összes lemondott foglalás és lemondott óra.
- A user „lemondási aránya” kizárólag a user saját maga által lemondott foglalásokat számítja a user terhére.
- Képlet: `user által lemondott foglalások / összes eredeti foglalás × 100`.
- Admin által törölt foglalás megmarad a lemondott foglalások és lemondott órák összesítésében, de nem növeli a user saját lemondási arányát.
- Nem kerül automatikus „jó/rossz” küszöbérték vagy figyelmeztetési határ bevezetésre külön üzleti döntés nélkül.
- Tételes lemondási lista kérhető le összes userre vagy egy kiválasztott userre.
- A tételes lista legalább: user, eredeti dátum, helyiség, kezdés, befejezés, lemondott óra, lemondás időpontja, kezdés előtti időtáv, lemondó személy, indok.
- A lemondási összesítőhöz és a tételes lemondási listához is külön CSV export tartozik.

## Audit és adatmegőrzés

- A lemondások történeti forrása a `booking_cancellations` és a kapcsolódó booking rekord.
- A lemondási riport nem töröl és nem módosít történeti adatot.
- A riportok csak aktív admin számára hozzáférhetők backend jogosultság-ellenőrzéssel.
