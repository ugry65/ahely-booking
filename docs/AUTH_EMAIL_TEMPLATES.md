# Supabase Auth e-mail sablonok

Állapot: technikai üzemeltetési dokumentáció, frissítve 2026-09-05.

## Jelszóbeállító / jelszó-visszaállító levél

Az A-Hely foglalási rendszer a Supabase Auth `recovery` levelét használja az új felhasználó biztonságos jelszóbeállításához és a későbbi jelszó-visszaállításhoz.

A levél követelményei:

- magyar nyelvű tárgy és tartalom;
- jelszó, ideiglenes jelszó vagy más hitelesítési titok nem szerepelhet a levélben;
- kizárólag a Supabase által létrehozott egyszer használható recovery hivatkozás használható;
- a hivatkozás a `{{ .ConfirmationURL }}` sablonváltozóból származik;
- a levél egyértelműen jelezze, hogy nem kezdeményezett kérés esetén figyelmen kívül hagyható.

A repository-ban verziózott forrás:

- `supabase/templates/recovery.html`
- `supabase/config.toml` → `[auth.email.template.recovery]`

Tárgy:

`Jelszó beállítása – A-Hely`

## Hosted Supabase környezetek

A `supabase/config.toml` és a HTML sablon a repository-ban a konfiguráció verziózott forrása és a lokális Supabase környezet beállítása. A hosted Supabase Auth e-mail sablonját ettől külön kell konfigurálni az adott projekt Auth-beállításaiban vagy a Supabase Management API-n keresztül.

Környezeti sorrend:

1. staging Auth recovery sablon frissítése;
2. staging tesztlevél küldése;
3. tárgy, magyar szöveg és recovery link ellenőrzése;
4. link megnyitása és jelszóbeállítási folyamat ellenőrzése;
5. csak sikeres staging UAT után és külön production jóváhagyással alkalmazható productionben.

A production Auth sablon módosítása nem része az automatikus staging promóciónak, és nem történhet implicit módon.

## Biztonsági ellenőrzés

A repository automatikus tesztje ellenőrzi, hogy a recovery sablon magyar, tartalmazza a `{{ .ConfirmationURL }}` hivatkozást, és nem tartalmaz kezdő- vagy ideiglenes jelszót.
