# A-Hely foglalási rendszer – Production readiness checklist

Státusz: előkészítés alatt. Production deploy csak minden kötelező kapu igazolt teljesülése után.

## 1. Fejlesztési fázis lezárása
- [ ] PR #90 teljes Application CI PASS.
- [ ] PR #90 teljes Database CI PASS.
- [ ] Utolsó üzleti módosítás stagingen deployolva: havi tételes aktív foglalásokban `Foglalás címe`, részletes CSV-ben is.
- [ ] Célzott staging UAT: Tréningterem foglalás címe a tételes havi lekérdezésben látható.
- [ ] Célzott staging UAT: Tréningterem csoportos foglalás default 5 000 Ft/óra és admin egyedi ár működik.
- [ ] Befizetések UI nem része az aktív foglaló rendszernek a 2026-08-25-i scope-döntés szerint.

## 2. Kötelező kritikus regresszió
- [ ] Normál foglalás.
- [ ] Átfedő foglalás blokkolása.
- [ ] Két egyidejű foglalási kísérletből csak egy sikerül.
- [ ] Jogosulatlan helyiségfoglalás blokkolása backend oldalon.
- [ ] 30 perces időegység.
- [ ] Minimum 1 órás foglalás.
- [ ] Előrefoglalási limitek.
- [ ] Tréningterem egyéni/csoportos szabályok.
- [ ] Tréningterem csoportos default és admin egyedi díj.
- [ ] Ismétlődő foglalások.
- [ ] Kivételdátumok.
- [ ] Módosítás és lemondás.
- [ ] Sávos / progresszív / Free díjazás.
- [ ] Havi összesítés és settlement snapshot.
- [ ] Auditnapló kritikus műveletekre.
- [ ] Admin/user jogosultságok és közvetlen URL/API hozzáférés.

## 3. Adatbiztonsági kapuk
- [ ] Production adatbázis külön a stagingtől.
- [ ] Napi automatikus backup igazoltan aktív.
- [ ] Backup-megőrzés dokumentálva.
- [ ] Elkülönített/off-platform backup megoldás vagy dokumentált alternatíva.
- [ ] Restore eljárás dokumentálva.
- [ ] Restore próba staging/sandbox környezetben ténylegesen végrehajtva és jegyzőkönyvezve.
- [ ] Foglalási és elszámolási adatok restore után konzisztencia-ellenőrzése PASS.
- [ ] Adatmegőrzési szabályok dokumentálva; automatikus végleges törlés nincs admin jóváhagyás nélkül.

## 4. Production konfiguráció
- [ ] Production Supabase secrets és connection stringek kizárólag secretként tárolva.
- [ ] Staging és production környezeti változók nem keverednek.
- [ ] Production Vercel projekt/domain véglegesítve.
- [ ] Auth redirect URL-ek és jelszó-visszaállítás production domainre konfigurálva.
- [ ] E-mail küldés production feladóról tesztelve.
- [ ] Admin fiókok és jogosultságok indulás előtt ellenőrizve.
- [ ] Nyilvános önregisztráció tiltva.

## 5. Migráció és rollback
- [ ] Production migrációk dry-run PASS.
- [ ] Production DB deploy csak explicit `PRODUCTION` megerősítéssel.
- [ ] Deploy előtti friss backup/restore pont rendelkezésre áll.
- [ ] Migráció utáni schema/migration status ellenőrzés PASS.
- [ ] Rollback/restore döntési eljárás dokumentálva.
- [ ] Production deploy alatt adatírási kockázat és szükséges karbantartási ablak értékelve.

## 6. UAT / üzleti elfogadás
- [ ] Admin napi naptár teljes folyamat ellenőrizve.
- [ ] Normál user teljes folyamat ellenőrizve.
- [ ] Mobil/tablet alapfunkciók ellenőrizve.
- [ ] Havi órák és fizetendő összesítő ellenőrizve valószerű mintákkal.
- [ ] Tételes aktív foglalások + Foglalás címe ellenőrizve.
- [ ] CSV/export kimenet ellenőrizve.
- [ ] Lemondási lista és statisztika ellenőrizve.
- [ ] Felhasználó-, helyiség-, díjazás- és jogosultság-admin funkciók ellenőrizve.

## 7. Független review
Kritikus részeknél külön második reviewer szükséges:
- [ ] foglalási motor és dupla foglalás elleni védelem;
- [ ] jogosultságok / RLS / SECURITY DEFINER függvények;
- [ ] adatmodell;
- [ ] díjszámítás és settlement snapshot;
- [ ] backup és restore stratégia;
- [ ] production deploy és rollback terv.

## 8. Go-live kapu
Production csak akkor indulhat, ha:
1. minden blokkoló CI/UAT hiba lezárt;
2. backup és tényleges restore próba bizonyított;
3. kritikus független review lezárt;
4. production konfiguráció ellenőrzött;
5. explicit üzleti jóváhagyás megtörtént.

A `main` branch production előtt csak review-zott és stagingen elfogadott állapotot tartalmazhat.
