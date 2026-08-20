# Skedda-szerű mobil naptár UX

UAT-döntés alapján a normál felhasználói foglalási felület mobilon a jelenlegi Skedda/AllBooked használati mintáját kövesse, hogy a rendszerre váltás minél kevesebb újratanulást igényeljen.

## Mobil napi naptár
- A felső sávban 7 egymást követő nap látszik.
- A kiválasztott nap vizuálisan kiemelt.
- Külön naptárvezérlővel tetszőleges dátumra lehet ugrani.
- A bal oldali órasáv vízszintes görgetésnél rögzített.
- A 07:00 kezdő időpontnak teljesen látszania kell.
- A naptár teljes felületén természetesen lehessen függőlegesen görgetni.
- Mobilon foglaláskijelölés csak long press után indul; ujjfelengedéskor azonnal megnyílik a foglalási ablak.

## Foglalási ablak
- Az egyszeri és ismétlődő foglalás ugyanabból az ablakból indul.
- Ismétlődési lehetőség csak olyan helyiségnél aktív, amelyhez a backend `list_repeatable_rooms` alapján az adott user jogosult.
- Az ismétlődés gyakorisága: napi, heti, kétheti, havi.
- Az ismétlődő foglalás továbbra is a meglévő `create_booking_series` backend folyamatot használja; az üzleti és jogosultsági szabályokat a UI nem írja felül.

A cél a Skedda használati logikájának követése, nem a szolgáltatás teljes vizuális másolata vagy fölösleges funkcióinak átvétele.
