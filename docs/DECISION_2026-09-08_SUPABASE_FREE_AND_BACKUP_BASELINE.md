# A-Hely foglalási rendszer – Supabase Free és backup/restore költségbaseline

Dátum: 2026-09-08
Státusz: **KÖTELEZŐ, AKTUÁLIS ÜZLETI/TECHNIKAI DÖNTÉS**

Ez a dokumentum felülír minden korábbi olyan javaslatot vagy leírást, amely a production indulását Supabase Pro/PITR előfizetéshez köti.

## 1. Költségdöntés

Az A-Hely foglalási rendszer production Supabase környezete **Free planon készül és üzemel**. A Supabase Pro/PITR **nem production előfeltétel és nem kötelező release-gate**.

A projekt célja kifejezetten az, hogy a havi fizetős SaaS-költség helyett saját, ellenőrzött adatbiztonsági és üzemeltetési védelmekkel használja a Free csomagot.

Ezért új tervezés, review vagy AI-javaslat **nem állíthatja**, hogy a Pro/PITR szükséges az adatbiztonsághoz vagy az éles induláshoz, kivéve ha a projektgazda később kifejezetten új üzleti döntést hoz.

## 2. Backup/restore baseline – már eldöntött és tesztelt terület

A backup/restore architektúrát nem kell újratervezni. A jóváhagyott modell:

- automatikus PostgreSQL logikai backup naponta négyszer: 08:00, 12:00, 16:00, 20:00 Europe/Budapest idő szerint;
- két egymástól független off-site cél:
  1. Google Drive;
  2. Backblaze B2;
- integritásellenőrzés checksum/read-back alapon;
- titkosított backup-kezelés;
- többgenerációs retention;
- Backblaze B2 Object Lock / törlés elleni védelem;
- dokumentált restore-folyamat;
- külön, izolált restore-drill.

A dual-target integritás és a restore-folyamat tesztelése megtörtént. A 2026-09-01-i izolált restore-drill bizonyította a visszaállítási folyamat működőképességét. A backup/restore mechanizmus tehát **nem nyitott architekturális döntés** és nem indok Supabase Pro előfizetésre.

A korábbi független review-ban az implementáció/release környezethez kapcsolódó trigger-, credential- és merge-státusz megállapítások külön release-hardening tételek voltak; ezek nem változtatják meg a fenti Free-plan és kétcélos backup üzleti/architekturális döntést.

## 3. Free plan automatikus pause – külön availability probléma

A Supabase Free inaktivitás miatti automatikus pause-ja **nem backup- és nem adatmegőrzési probléma**. Ezt külön availability/monitoring feladatként kezeljük.

A production rendszernek rendszeres, biztonságos, read-only health-checket kell futtatnia, amely valódi Supabase/PostgreSQL lekérdezést végez és így az elérhetőséget is ellenőrzi. A cél kettős:

1. az adatbázis és az alkalmazás működésének proaktív ellenőrzése;
2. rendszeres legitim adatbázis-aktivitás biztosítása a Free projekt számára.

A health-check:

- nem módosíthat üzleti adatot;
- nem hozhat létre mesterséges foglalást/audit/elszámolási sort;
- nem adhat ki személyes adatot vagy secretet;
- hibát és recoveryt a monitoringnak jeleznie kell.

A production anti-pause health-check megvalósítása/ütemezése külön operációs feladat; **nem helyettesíti** a már meglévő backup/restore rendszert.

## 4. Dokumentációs precedencia

Backup/Supabase költség és availability témában a források sorrendje:

1. ez a dokumentum;
2. `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`;
3. `docs/PRODUCTION_INFRASTRUCTURE_DECISIONS_2026-08-25.md` (2026-08-31-i Free-plan döntés);
4. az aktuális backup/restore runbook és implementációs dokumentumok;
5. régebbi architektúra/backup baseline dokumentumok csak ott, ahol nem mondanak ellent a fentieknek.

Kifejezetten **SUPERSEDED** minden olyan korábbi mondat, amely szerint:

- productionhöz legalább Supabase Pro szükséges;
- a Supabase menedzselt napi backup kötelező második réteg;
- PITR production előtt kötelező;
- a Pro/PITR költsége production readiness feltétel.

## 5. AI/fejlesztési szabály

Minden új beszélgetés, review és fejlesztési feladat előtt ezt a döntést kötelező figyelembe venni. A Free-plan döntés vagy a már kidolgozott kétcélos backup/restore újranyitása csak a projektgazda kifejezett új döntésére történhet.
