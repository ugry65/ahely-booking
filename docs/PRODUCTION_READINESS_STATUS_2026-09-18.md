# Élesítés előtti állapotjelentés

**Dátum:** 2026-09-18  
**Állapot:** dokumentációs összesítés, nem önálló éles környezeti módosítás

## Lezárt vagy meglévő funkciók

### Papp Dalma próbaadatainak kivezetése

A projektgazda visszajelzése alapján a Papp Dalma-féle migrációs próbaadatok kivezetése az éles rendszerben megtörtént. Jelenleg nincs hozzá aktív éles foglalás. Ezt a lépést nem kell újra végrehajtani.

### Adminisztrátori foglalás más nevében

A funkció rendelkezésre áll:

- a foglalási felületen adminisztrátor kiválaszthatja a célfelhasználót;
- a szerveroldal a célfelhasználót csak admin jogosultság esetén fogadja el;
- az adatbázis RPC-je szintén kikényszeríti, hogy nem admin ne foglalhasson más nevében;
- a foglalás és az audit/outbox esemény a kiválasztott felhasználóhoz kötődik.

A működés kód- és jogosultsági szinten ellenőrzött. Az élesítés dokumentációjához még a végleges kézi UAT-bejegyzés tartozik.

### Foglalási visszaigazoló e-mail

A projektkövetelmény szerint az első éles verzióban szükséges. A projektgazda korábbi UAT-visszajelzése szerint a folyamat tesztelve és működőképes volt.

Fontos: ez külön folyamat a Supabase Auth jelszó-visszaállító e-mailjétől. Az élesítési jegyzőkönyvben külön kell rögzíteni a foglalási visszaigazolás ellenőrzését.

## Migrációs állapot

A jelenlegi migrációs eljárás egy CSV-fájlban egy ügyfelet kezel. Ez kontrollált, újrafuttatható ügyfél-szintű migrációra készült, és a Papp Dalma-féle próbaadatok törlése nem változtatja meg ezt a működést.

A több ügyfelet és több foglalást tartalmazó tömeges import jelenleg nincs engedélyezve: a meglévő eljárás az ilyen fájlt szándékosan elutasítja. Tömeges migráció csak külön fejlesztés és célzott regressziós teszt után használható.

## További élesítési feltételek

1. A kézi UAT-jegyzőkönyv frissítése a már eldöntött pontokkal:
   - admin foglalása más nevében: szükséges és implementált;
   - foglalási visszaigazoló e-mail: szükséges, korábban tesztelt;
   - heti nézet: nem első élesítési blokkoló;
   - tömeges migráció: külön, későbbi fejlesztés.
2. A foglalási visszaigazoló e-mail külön, dokumentált éles ellenőrzése.
3. A production backup ütemezés és a sikeres restore-drill bizonyítékának lezárása. Ezt nem aktiválom automatikusan, mert éles környezeti és adatmegőrzési döntés.
4. Az éles migrációk csak jóváhagyott, egy-ügyfeles fájlokkal történjenek, amíg a tömeges import külön fejlesztése el nem készül.

## Döntést igénylő külön fejlesztés

Ha tömeges migráció szükséges, a javasolt működés:

- minden ügyfél önálló atomi egység;
- egy hibás ügyfél teljesen visszagörgethető;
- a többi hibátlan ügyfél importja folytatható;
- a végén ügyfelenként külön siker/hiba összesítő készül.

Ennek véglegesítése után készíthető el a tömeges import és a hozzá tartozó tesztcsomag.
