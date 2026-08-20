# A-Hely – ismétlődő foglalás és előrefoglalási szabályok

Dátum: 2026-08-21

Állapot: **kötelező üzleti baseline**

Ez a dokumentum a foglalási jogosultság, az ismétlődés és az előrefoglalási limitek elsődleges részletszabálya. UI- vagy backend-refaktor ezeket nem írhatja felül külön üzleti döntés nélkül.

## Normál user

- A normál user minden **normál helyiségben**, amelyre `can_book` foglalási jogosultsága van, egyszeri **és ismétlődő** foglalást is létrehozhat.
- Normál helyiségnél az ismétlődési jogosultság nem külön kézi kapcsoló: a `can_repeat` effektív jogosultság a `can_book` jogot követi.
- A normál helyiségek alapértelmezett előrefoglalási limite **90 nap**.
- A normál előrefoglalási limit adminisztrációból állítható; a jóváhagyott userenkénti felülírás továbbra is alkalmazható.
- A Tréningterem külön szabály: normál user ott **nem készíthet ismétlődő foglalást**.
- A Tréningterem egyszeri foglalásának külön előrefoglalási limitje adminból állítható; jelenlegi default 10 nap.

## Admin

- Admin bármely aktív helyiségben készíthet egyszeri és ismétlődő foglalást.
- Admin Tréningteremben is készíthet ismétlődő foglalást.
- Adminra nem vonatkozik a normál user 90 napos előrefoglalási limitje és a Tréningterem normál-user limitje.
- Admin más felhasználó nevében is eljárhat a meglévő admin jogosultsági szabályok szerint.
- Az admin sorozatát normál-user előrefoglalási limit nem rövidítheti meg és nem utasíthatja el.

## Szerveroldali kötelezettség

- A szabályokat backend/RPC oldalon kell kikényszeríteni; a UI önmagában nem biztonsági határ.
- `effective_room_permissions`: normál helyiségnél effektív `can_repeat = can_book`; Tréningteremnél normál user számára `can_repeat = false`.
- `list_repeatable_rooms` ennek az effektív jogosultságnak megfelelő helyiségeket adhatja vissza; admin minden aktív helyiséget ismételhetőként kaphat meg.
- `create_booking_series` normál usernél csak foglalható normál helyiségre engedhet sorozatot, Tréningteremre nem; admin bypass kötelező.
- Az egyes létrejövő alkalmaknál a foglalási ütközés-, nyitvatartás-, időrács- és egyéb integritási ellenőrzések továbbra is kötelezők.

## Kötelező regressziós esetek

1. normál user + 2.Szoba + ismétlődés a saját előrefoglalási limitjén belül → sikeres;
2. normál user + bármely engedélyezett normál szoba + ismétlődés → sikeres;
3. normál user + normál szoba + saját előrefoglalási limiten túl → elutasított;
4. normál user + Tréningterem + ismétlődés → elutasított;
5. admin + normál szoba + 90 napon túl → a normál-user limit miatt nem utasítható el;
6. admin + Tréningterem + ismétlődés → sikeres;
7. admin + hosszabb sorozat → normál-user előrefoglalási limit nem blokkolhatja.

## Kapcsolódó dokumentumok

- `A-Hely_Foglalasi_Rendszer_PROJEKT_KONTEXTUS.md`
- `docs/BOOKING_UI_UX_BASELINE.md`
- `docs/FUNKCIONALIS_UAT_CHECKLIST.md`

Ha ezekben régebbi, általánosabb megfogalmazás szerepel, a 2026-08-21-i fenti döntés az irányadó, amíg új dokumentált üzleti döntés nem születik.
