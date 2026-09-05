# Supabase Auth e-mail sablonok

Állapot: technikai üzemeltetési dokumentáció, frissítve 2026-09-05.

## Jelszóbeállító / jelszó-visszaállító levél

Az A-Hely foglalási rendszer a Supabase Auth `recovery` levelét használja az új felhasználó biztonságos jelszóbeállításához és a későbbi jelszó-visszaállításhoz.

A levél követelményei:

- magyar nyelvű tárgy és tartalom;
- jelszó, ideiglenes jelszó vagy más hitelesítési titok nem szerepelhet a levélben;
- kizárólag a Supabase által létrehozott egyszer használható recovery token használható;
- a levél `{{ .TokenHash }}` és `{{ .RedirectTo }}` sablonváltozókból épít közvetlen alkalmazás-linket;
- az alkalmazás callbackje kizárólag `type=recovery` token hash-t fogad, majd `verifyOtp` hívással hozza létre a sessiont;
- a megoldás nem függ a jelszó-visszaállítást indító böngésző PKCE cookie-jától, ezért másik böngészőben vagy eszközön is működhet;
- a levél egyértelműen jelezze, hogy nem kezdeményezett kérés esetén figyelmen kívül hagyható.

A repository-ban verziózott forrás:

- `supabase/templates/recovery.html`
- `supabase/config.toml` → `[auth.email.template.recovery]`
- `src/app/auth/callback/route.ts`

Tárgy:

`Jelszó beállítása – A-Hely`

## Hosted Supabase környezetek

A `supabase/config.toml` és a HTML sablon a repository-ban a konfiguráció verziózott forrása és a lokális Supabase környezet beállítása. A hosted Supabase Auth e-mail sablonját ettől külön kell konfigurálni az adott projekt Auth-beállításaiban vagy a Supabase Management API-n keresztül.

A teljes `supabase config push` jelenleg nem része a staging deploynak. Ennek oka, hogy a repository `config.toml` fájlja lokális URL-beállításokat is tartalmaz; ezek kontrollálatlan feltöltése felülírhatná a hosted Auth Site URL / redirect konfigurációt. Hosted környezetben ezért kizárólag a recovery tárgy és tartalom célzott frissítése megengedett.

Környezeti sorrend:

1. staging Auth recovery sablon célzott frissítése;
2. staging tesztlevél küldése;
3. tárgy, magyar szöveg és recovery link ellenőrzése;
4. a link megnyitása lehetőleg az indítótól eltérő böngészőben / privát ablakban is;
5. jelszóbeállítás és az ezt követő bejelentkezés ellenőrzése;
6. csak sikeres staging UAT és független review után, külön production jóváhagyással alkalmazható productionben.

A production Auth sablon módosítása nem része az automatikus staging promóciónak, és nem történhet implicit módon.

## Biztonsági ellenőrzés

A repository automatikus tesztje ellenőrzi, hogy a recovery sablon magyar, token hash alapú eszközfüggetlen recovery linket használ, a callback recovery tokenre `verifyOtp` hívást végez, és a levél nem tartalmaz kezdő- vagy ideiglenes jelszót.
