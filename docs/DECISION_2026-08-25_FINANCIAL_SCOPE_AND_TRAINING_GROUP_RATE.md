# 2026-08-25 – Pénzügyi scope és Tréningterem csoportos díj döntések

## Tréningterem csoportos használat

- A Tréningterem csoportos használatának alapértelmezett díja **5 000 Ft/óra**.
- Admin új foglalás vagy új ismétlődő sorozat létrehozásakor az adott foglalás/sorozat óradíját felülírhatja.
- A felülírt díjat a foglaláshoz kell rögzíteni; későbbi default díjváltozás nem írhatja át visszamenőleg a meglévő foglalások díját.
- Az admin díjfelülírás auditálandó.
- A szabály kizárólag a **Tréningterem Csoportos használatára** vonatkozik, nem a külön „Csoport szoba” helyiségre.
- Az elszámolás a foglaláshoz rögzített tényleges csoportos óradíjat használja.

## Befizetések kezelése – aktuális scope

- A foglaló rendszer aktív admin felületén **nem kezeljük a befizetések könyvelését**.
- A foglaló rendszer feladata továbbra is a foglalásokból származó órák és a számított fizetendő összeg megbízható előállítása.
- A tényleges befizetés rögzítése és könyvelése a külön pénzügyi elszámolási folyamatban történik; az admin ott jelzi, ki fizetett, és a pénzügyi/Skedda agent könyveli a befizetést.
- Emiatt a `Befizetések` menüpont és az aktív befizetés-rögzítő UI nem része a foglaló rendszer jelenlegi használati scope-jának.
- A korábban stagingre felvitt payment adatbázis-migrációkat nem töröljük vissza. A migrációs történetet és az esetleges adatokat megőrizzük; a backend réteg jelenleg parkoltatott, nem aktív felhasználói funkció.
- Ha később a befizetéskezelést visszahozzuk a foglaló rendszerbe, az külön üzleti döntés és UAT tárgya lesz.

## Adatbiztonsági következmény

A már alkalmazott adatbázis-migrációk visszabontása helyett az alkalmazás UI-jából kapcsoljuk ki a payment funkciót. Ez minimalizálja a migrációs történet, auditálhatóság és staging/production konzisztencia sérülésének kockázatát.
