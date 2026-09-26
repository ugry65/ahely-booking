# Döntés – Production backup retention és Backblaze B2 Object Lock

Eredeti döntés: 2026-08-31  
Felülíró üzleti döntés: **2026-09-26**  
Státusz: **ELFOGADOTT, IMPLEMENTÁCIÓ/DRY-RUN ALATT**

## 1. Aktuális, kötelező retention policy

A 2026-08-31-i 14 nap / 90 nap / 24 hónap policyt a projektgazda 2026-09-26-án felülírta.

- **0–7 nap:** minden sikeres restore-pont megmarad, normál esetben napi 4;
- **8–30 nap:** hetente 1 restore-pont marad;
- **30 napnál régebbi:** törölhető;
- a heti restore-pont az adott Europe/Budapest szerinti ISO-hét legutolsó sikeres backupja.

A korábbi napi/havi hosszú távú generációs retention megszűnik.

## 2. Backblaze B2 Object Lock

- Governance mód;
- legalább 30 napos védelem;
- a lock szándékosan erősebb a 8–30 napos heti ritkításnál.

Következmény: Google Drive-on 8–30 nap között fizikailag végrehajtható a heti ritkítás. B2-n az Object Lock miatt **minden 30 napon belüli restore-pont fizikailag megmarad**. Ez nem policy-hiba, hanem szándékos törlésvédelem. A 30 napnál régebbi B2 artifact a lock lejárta után törölhető.

## 3. Biztonsági invariánsok

1. 0–7 nap között egyik célhelyen sem ritkítható backup.
2. B2-n 30 napon belül automatikus törlés nem történhet.
3. Ismeretlen fájlnév nem törölhető.
4. Felismert backup hiányzó checksum sidecarral fail-closed hibát okoz.
5. Apply előtt mindkét célhely teljes preflightja lefut; ismert hibás második cél esetén az első sem módosulhat.
6. Artifact és `.sha256` sidecar párban kezelendő.
7. Dry-run az alapértelmezett mód.
8. Manuális apply külön `RETENTION` megerősítést igényel.
9. Scheduled apply csak akkor indulhat, ha `RETENTION_AUTOMATION_ENABLED=true` és `RETENTION_POLICY_VERSION=2026-09-26-v2`.
10. Az új policy production automatikus aktiválása előtt kötelező a valós Google Drive + B2 dry-run exact keep/delete lista ellenőrzése.

## 4. Bevezetési sorrend

1. kód;
2. automatikus retention teszt;
3. workflow gate teszt;
4. PR CI;
5. production workflow **dry-run**;
6. exact Google Drive/B2 keep/delete lista emberi ellenőrzése;
7. csak ezután engedélyezhető a v2 scheduled apply.

A régi policyvel készült korábbi dry-run nem fogadható el az új policy bizonyítékaként.

## 5. Indoklás

A backup és monitoring hibáknak napokon belül láthatóvá kell válniuk. Az A-Hely jelenlegi üzemi kockázatához egy hét teljes sűrűség, majd egy hónapig heti restore-pont megfelelő kompromisszum. A B2 30 napos Object Lock külön védelmi réteg marad.

## 6. Későbbi felülvizsgálat

A policy csak dokumentált új üzleti döntéssel változtatható. A foglalási/elszámolási üzleti adatok adatmegőrzési szabálya ettől külön kérdés: ez a dokumentum kizárólag a technikai backup-generációk retentionjét szabályozza.
