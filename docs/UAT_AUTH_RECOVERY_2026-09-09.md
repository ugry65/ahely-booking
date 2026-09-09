# Staging UAT – aktiválás, jelszóbeállítás és jogosultság

Dátum: 2026-09-09
Környezet: staging
Kapcsolódó issue: #116

## Eredmény

A teljes végponttól végpontig auth folyamat sikeresen ellenőrizve.

Bizonyított lépések:

1. A Supabase staging custom SMTP Resenddel működik.
2. A levél feladója: `A-Hely Foglalás <foglalas@a-hely.com>`.
3. Az aktiváló / jelszóbeállító levél megérkezik.
4. A recovery link másik böngészőből/eszközről is a staging `/jelszo-visszaallitas` oldalra visz.
5. Új jelszó sikeresen beállítható.
6. A felhasználó az új jelszóval sikeresen be tud jelentkezni.
7. Admin által kiosztott helyiségjog azonnal érvényesül; a felhasználó látja a jogosult szobát.

## UAT közben szükséges konfigurációjavítások

Supabase staging:

- Site URL: `https://ahely-booking-git-staging-a-hely.vercel.app`
- Redirect URL allowlist tartalmazza a staging aliast.

Vercel:

- `SITE_URL` külön Preview / `staging` branch értéke:
  `https://ahely-booking-git-staging-a-hely.vercel.app`
- a módosítás után staging redeploy történt.

## Biztonsági megjegyzés

A dokumentáció nem tartalmaz:

- felhasználói jelszót;
- recovery tokent vagy teljes recovery URL-t;
- Resend API kulcsot;
- SMTP jelszót vagy egyéb secretet.

## Következtetés

A staging aktiválási és jelszó-helyreállítási folyamat üzleti UAT-ja sikeres. A következő külön fejlesztési tétel az admin műveleti gombok azonnali vizuális visszajelzése (#113).
