# Jelszómódosítás visszajelzése – 2026-10-29

A Supabase Auth `same_password` hibakódja esetén a jelszó-visszaállító oldal
pontos üzenetet mutat: „Az új jelszó nem egyezhet meg a jelenlegi jelszavaddal.
Adj meg másik jelszót.” Korábban csak általános sikertelenséget jelzett.

A kód alapján választunk, nem a szolgáltató hibaüzenetének szövegéből.
Más hibák általános üzenete és a sikeres mentés útvonala változatlan.
Jelszó vagy nyers Auth-hiba nem kerül az URL-be vagy naplóba.

Négy szerverakció-regressziós teszt ellenőrzi az azonos jelszó, eltérő/hiányzó
hibakód és sikeres válasz útját, mockolt Auth-válaszokkal. Ez nem valódi fiók
jelszócseréje és nem teljes e-mailes visszaállítási E2E-bizonyíték.

Csak alkalmazáskód és teszt változik; adatbázis-migráció, Auth-konfiguráció,
foglalási vagy pénzügyi adat módosítása nem szükséges.

Szolgáltatói referencia: https://supabase.com/docs/guides/auth/debugging/error-codes
