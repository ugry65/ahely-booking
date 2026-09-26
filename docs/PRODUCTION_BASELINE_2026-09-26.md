# A-Hely foglalási rendszer – production baseline és átadási státusz

**Állapotdátum:** 2026-09-26  
**Repository:** `ugry65/ahely-booking`  
**Production felhasználói URL:** `https://foglalas.a-hely.com`  
**Release baseline:** `64009df07306d0f4a5e29e6ec80a9781a20868b8`

## 1. Production elérés

A custom domain közvetlenül a Vercel production projekthez kapcsolódik. A MediaCenter csak DNS-szolgáltató ebben az útvonalban; nincs külön MediaCenter virtuálhost/mappa. A `foglalas` CNAME a Vercel által adott célra mutat. Vercel kezeli a TLS-t.

Ellenőrzött: DNS felismerés PASS; HTTPS PASS; HTTP 200; login oldal PASS; mobil böngésző PASS; inkognitó PASS.

A `ahely-booking.vercel.app` technikai alias megtartható diagnosztikai célra, de felhasználói kommunikációban a custom domain az elsődleges.

## 2. Aktuális release

PR #215 / merge `64009df...`:
- mobil Díjszabás nézet responsive kártyás megjelenítése;
- oldal-szintű mobil horizontal overflow megszüntetése ezen az oldalon;
- elavult Papp Dalma próbaimport-visszavonó UI és klienslogika eltávolítása.

## 3. Booking és adatbiztonság

- DB-szintű room overlap exclusion constraint aktív.
- `btree_gist` extension productionben az `extensions` sémában.
- Security Advisor `extension_in_public` finding megszűnt.
- Production migration-test booking cleanup kontrollált exact-scope művelettel és auditmegőrzéssel megtörtént.
- Auth/profile adatot a cleanup nem törölt.
- A production email UAT szándékos lemondott booking/audit nyomot hagyott; ezért a bookings darabszámot nem szabad automatikusan 0-nak feltételezni.

## 4. Booking e-mail

Transactional outbox a hiteles architektúra. Booking DB-művelet elsődleges, e-mail másodlagos. Provider hiba nem rollbackeli a bookingot; az outbox retry-képes.

- staging real-provider recurring create/cancel UAT PASS;
- production kontrollált create e-mail PASS;
- production kontrollált cancel e-mail PASS;
- production send mód aktív;
- staging normál mód capture.

Aktuális booking-email provider: Resend. A korábbi MediaCenter SMTP terv történeti.

## 5. Pricing

2026-10-01-től:
- 1–15 óra: 2500 Ft/óra;
- >15–60 óra: 1900 Ft/óra;
- >60 óra: 1700 Ft/óra;
- Tréningterem csoportos alapdíj: 5000 Ft/óra.

Történeti 2026. szeptemberi szabályok reprodukálhatók. Precedencia: booking override → user override → központi pricing / Training room base. Pricing UAT: 12/12 PASS.

## 6. Backup / restore / monitoring

Production backup: naponta 08:00, 12:00, 16:00, 20:00 Europe/Budapest szerint. Titkosított, checksumolt artifact két off-site célra: Google Drive + Backblaze B2.

Izolált restore drill PASS. Heartbeat kontrollált fail → várakozás → recovery útvonal mind a 08/12/16/20 slotra PASS. B2 Object Lock Governance/30d igazolt.

### 6.1 Új retention policy – 2026-09-26

Felülírja a korábbi hosszabb retention tervet:
- 0–7 nap: minden backup (4/nap);
- 8–30 nap: heti 1;
- >30 nap: törölhető;
- B2 Object Lock legalább 30 nap.

Bevezetési gate: implementáció + automatikus teszt → dry-run mindkét célra → exact keep/delete lista ellenőrzés → csak utána apply. A régi policy dry-runja nem bizonyítja az új policyt.

## 7. PWA / mobil

Első production scope: lightweight online-only webapp.
- manifest;
- standalone metadata;
- app icon + Apple touch icon;
- nincs service worker;
- nincs offline booking/background sync;
- nincs offline üzleti adat-cache.

Technikai metadata PASS és custom-domain mobil böngészős smoke PASS. Még dokumentálandó: valódi iPhone Add to Home Screen + standalone; Android Chrome valós smoke.

## 8. Migráció / cutover

A technikai production infrastruktúra működik, de valódi ügyfél/booking migráció még nem történt meg. Cutover sorrend:
1. végleges forrásexport és mapping;
2. staging import;
3. reconciliation;
4. friss production backup;
5. production import;
6. production reconciliation;
7. auth/hozzáférés smoke;
8. üzemi átállás.

Production nem örököl staging bookingokat.

## 9. GitHub issue státusz

2026-09-26 lezárva:
- #31 backup automatizálás – completed;
- #73 onboarding/auth – completed;
- #75 helyiségcsoport/jogosultság – completed;
- #82 havi díjazás – completed;
- #85 Cloudflare/OpenNext preview – not planned.

Nyitva marad, mert tényleges acceptance/scope van hátra:
- #40 recurring exception-date calendar UX;
- #44 adminból állítható advance-booking limit UI;
- #105 PWA – Android/valódi install acceptance és a régi issue scope-jának rendezése;
- #109 mobil UX – Android Chrome / maradék valós-device acceptance.

## 10. Production módosítási szabály

Production DB/Auth/config/email/monitoring módosítás továbbra is explicit projektgazdai jóváhagyást igényel. Read-only audit megengedett. Kritikus adatbiztonsági/pénzügyi változtatásnál független review szükséges.

## 11. Következő sorrend

1. új retention policy implementáció + teszt + dry-run;
2. maradék mobil/PWA valós-device acceptance;
3. dokumentáció konzisztencia;
4. valódi migrációs cutover előkészítése;
5. friss backup;
6. production import + reconciliation;
7. üzemi átállás.
