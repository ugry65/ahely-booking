# Auth password reset e-mail production baseline

Dátum: 2026-09-13  
Státusz: bizonyított, regresszióvédett production baseline

## Döntés és hatókör

Az A-Hely production jelszó-visszaállítási folyamata sikeresen, teljes végponttól végpontig tartó teszten ment át. Az alábbi konfiguráció működő production baseline, ezért Auth-, SMTP-, `SITE_URL`-, redirect- vagy e-mail-sablon változtatás csak célzott regressziós ellenőrzéssel történhet.

Ez a dokumentum állapotot rögzít. Nem ad felhatalmazást production Supabase Auth-, SMTP- vagy Vercel environment-beállítás automatikus módosítására.

## Bizonyított production konfiguráció

- Supabase production projekt: `ahely-booking-production`
- Supabase project ref: `yasrmxwjojepessivhmc`
- Supabase Authentication → URL Configuration:
  - Site URL: `https://ahely-booking.vercel.app`
  - Redirect URL: `https://ahely-booking.vercel.app/auth/callback`
- Vercel production environment:
  - `SITE_URL=https://ahely-booking.vercel.app`
- Supabase Auth custom SMTP: aktív
- SMTP szolgáltató: Resend
- Auth e-mail feladó: az A-Hely saját e-mail-címe
- Reset password e-mail sablon: magyar nyelvű
- A sablon technikai reset linkje: `{{ .ConfirmationURL }}`

## Bizonyított production teszteredmény

Az end-to-end production ellenőrzés eredménye PASS:

1. a reset e-mail megérkezik;
2. a reset link nem localhostra, hanem a production domainre mutat;
3. az `/auth/callback` feldolgozza a visszahívást;
4. a `/jelszo-visszaallitas` oldal elérhető;
5. a jelszó sikeresen megváltoztatható;
6. az új jelszóval a belépés sikeres.

## Korábbi hiba és gyökérok

A korábbi reset link `localhost:3000` címre irányított. A gyökérok az volt, hogy a production Supabase Auth Site URL és redirect konfiguráció nem volt helyesen rögzítve.

A Supabase alapértelmezett Auth SMTP használata mellett a szükséges reset sablon nem volt szerkeszthető. A custom Resend SMTP aktiválása után a reset e-mail sablon magyar nyelvre állíthatóvá vált, miközben a technikai link továbbra is a Supabase által előállított `{{ .ConfirmationURL }}` maradt.

## Két külön Resend-alrendszer

A Supabase Auth custom SMTP és az alkalmazás booking e-mail Resend transportja két külön rendszer:

- a Supabase Auth custom SMTP az Auth e-maileket kezeli, például az aktiválást és a jelszó-visszaállítást;
- a booking e-mail transport az alkalmazás foglalási értesítéseit továbbítja.

Az egyik rendszer konfigurációja, sablonja vagy sikeres tesztje nem bizonyítja a másik helyes működését. Módosításukat és regressziós ellenőrzésüket külön kell kezelni.

## Kötelező regressziós ellenőrzés

Minden Auth-, custom SMTP-, `SITE_URL`-, Supabase redirect- vagy Auth e-mail-sablon változás után production-szerű környezetben kötelező ellenőrizni:

1. új reset e-mail indítható és megérkezik;
2. a tárgy és a tartalom magyar nyelvű;
3. a feladó az A-Hely saját címe;
4. a reset link a production domainre mutat, nem localhostra vagy más környezetre;
5. az Auth callback sikeresen működik;
6. a jelszóváltás sikeres;
7. az új jelszóval a belépés sikeres.

Ha bármelyik pont hibás, a változtatás nem release-ready, és a korábbi bizonyított konfigurációt kell referenciának tekinteni.
