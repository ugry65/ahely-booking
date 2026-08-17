# Supabase Auth környezeti ellenőrzőlista

Ezt a listát minden staging és production Supabase-projektnél külön végre kell hajtani. A repository `config.toml` fájlja csak a helyi környezetet konfigurálja.

## Auth beállítások

- E-mail+jelszó bejelentkezés engedélyezett.
- Nyilvános regisztráció tiltott.
- Anonymous sign-in tiltott.
- Meghívó és jelszó-visszaállító e-mail sablon ellenőrzött.
- Productionben saját SMTP beállítva és próbalevéllel ellenőrizve.
- A jelszóházirend legalább 12 karaktert követel.

## URL-ek

- A Supabase Site URL pontosan az adott alkalmazáskörnyezet HTTPS-originje.
- A redirect allowlist csak az adott környezet `/auth/callback` végpontját és a szükséges preview originöket tartalmazza.
- Production allowlistben nincs localhost, tetszőleges wildcard vagy idegen origin.
- Az alkalmazás szerveroldali `SITE_URL` változója ugyanarra a megbízható originre mutat.

## Környezeti változók

- `NEXT_PUBLIC_SUPABASE_URL`: az adott Supabase-projekt URL-je.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: kizárólag a publishable kulcs.
- `SUPABASE_SERVICE_ROLE_KEY`: csak szerveroldali secret store-ban; kliensbundle-ben és repository-ban tilos.
- `SITE_URL`: az adott alkalmazáskörnyezet megbízható HTTPS-originje.

## Kiadás előtti próba

1. Nem meghívott e-maillel a regisztráció sikertelen.
2. Admin meghívása a helyes környezet callbackjére érkezik.
3. Meghívott user be tudja állítani a jelszavát.
4. Jelszó-visszaállítás nem árulja el, létezik-e az e-mail-cím.
5. Inaktív profil érvényes Auth sessionnel sem jut be az alkalmazásba.
6. Normál user közvetlen Data API-kéréssel sem olvas más profilt, adminmezőt vagy pénzügyi adatot.
7. A callback külső, backslash-alapú és nem allowlistelt `next` célokat `/foglalasok` útvonalra cserél.

Az ellenőrzés dátumát, végrehajtóját és a staging/production eredményt a release-jegyzőkönyvben rögzíteni kell. Secret érték nem kerülhet a jegyzőkönyvbe.
