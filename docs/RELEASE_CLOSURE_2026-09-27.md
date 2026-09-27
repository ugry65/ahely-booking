# Release lezárás – 2026-09-27

## Állapot
A 2026-09-27-i fejlesztési csomag staging UAT után projektgazdai jóváhagyással productionbe került.

- production: https://foglalas.a-hely.com
- release commit: `2ca1868dfaa82c5fc3b7d53cf1031b1de70351e8`
- PR #233 merge-elve; Vercel production READY
- Application checks, Database tests, Release evidence: PASS
- projektgazdai production UAT: PASS

## Lezárt változások
### Több felhasználó egy AllBooked CSV-ben
A staging UAT 9 user / 446 booking / 2024 óra reconciliationnel PASS. A batch DB-import tranzakciós; DB-hibánál rollback. Az Auth-kompenzáció csak bizonyítottan üzleti adat nélküli, új usert takaríthat vissza. Migráció booking e-mailt nem generál. #224 és #226 lezárva.

### Havi elszámolás – alkalmazott óradíj
Az Összes óra mellett megjelenik a ténylegesen alkalmazott óradíj; vegyes tarifa esetén több díj. CSV/XLSX is tartalmazza. Snapshotnál revision pricing_breakdown, live hónapnál pricing motor pricing_breakdown. #228 lezárva.

### Visszamenőleges egyedi user óradíj
Végleges üzleti döntés:
- egyedi user óradíj: lehet visszamenőleges;
- központi sávos díjszabás: csak jövőbeli;
- Tréningterem globális csoportos díja: csak jövőbeli.
A user-módosítás admin-only, indokolt, auditált és időben verziózott. A global future-only szabály regressziótesztelt. #230 eredeti, szélesebb scope-ja superseded; PR #231 nem merge-elendő.

### Admin user e-mail módosítás
Admin kötelező indokkal módosíthatja a bejelentkezési e-mailt. Aktív admin ellenőrzés, explicit actor, Auth/profile duplikációvédelem, DB finalize+audit és finalize-hibánál best-effort Auth rollback. User ID/történeti üzleti adat nem változik. RPC közvetlenül service_role-only. #232 lezárva; staging és production UAT PASS.

## Production DB
Sikeresen alkalmazva: admin_user_email_change; monthly_summary_pricing_breakdown; allow_retroactive_user_hourly_rate; email_finalize_accept_auth_profile_sync; email_change_explicit_actor; restore_future_only_global_pricing.

Post-deploy PASS: explicit-actor e-mail RPC-k; summary pricing_breakdown; central future-only; Training future-only; user rate retroaktív.

## Auth / jelszóbeállító e-mail
Új döntés:
- 1 óra túl rövid;
- kívánt 48 óra hosted Supabase-ban nem állítható, maximum 86400 sec;
- elfogadott cél: **24 óra / 86400 sec**;
- stagingben manuálisan beállítva; >1 órás Supabase security recommendation tudatosan vállalt kompromisszum;
- productionben ugyanez külön beállítandó, utána reset/aktiváló regressziós ellenőrzés kell.

## Elhalasztott: ideiglenes jelszó
Felmerült userenként egyedi véletlen ideiglenes jelszó + kötelező first-login password change. **2026-09-27 döntés: egyelőre nem implementáljuk.**
Ha később újranyitjuk: erős egyedi temp password; kötelező csere; booking UI/API ne legyen megkerülhető csere előtt; jelszó ne kerüljön app DB/audit payloadba; forgot-password maradjon; staging security/UAT kötelező.

## Nyitott operatív pont
Production Email OTP expiration még 86400 sec-re állítandó és célzott Auth regresszióteszt szükséges. Ez nem része a lezárt feature-kódnak.
