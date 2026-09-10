# Skedda-szerű mobil naptár UX

UAT-döntés alapján a normál felhasználói foglalási felület mobilon a jelenlegi Skedda/AllBooked használati mintáját kövesse, hogy a rendszerre váltás minél kevesebb újratanulást igényeljen.

A teljes, regresszióvédett foglalási UI/UX baseline forrása: `docs/BOOKING_UI_UX_BASELINE.md`. Ez a fájl a mobil Skedda-minta tömör szakmai kivonata.

## Mobil napi naptár
- A felső sávban 7 egymást követő nap látszik: a kiválasztott nap és a következő 6 nap.
- A kiválasztott nap vizuálisan, kör alakban kiemelt.
- Külön naptárikon nyit havi naptárválasztót; innen tetszőleges dátumra lehet ugrani.
- A bal oldali órasáv vízszintes görgetésnél rögzített/sticky, nem csúszhat együtt a szobákkal.
- A 07:00 kezdő időpontnak teljesen látszania kell.
- Az egész órás vízszintes vonalak hangsúlyosabbak, a félórás vonalak finomabbak; az óracímkék az egész órás vonalakhoz igazodnak.
- A naptár teljes felületén természetesen lehessen függőlegesen görgetni.
- Mobilon foglaláskijelölés csak long press után indul; normál scroll ne indítson foglalást.
- Ujjfelengedéskor azonnal megnyílik a foglalási ablak, mobilon nincs köztes „Foglalás” gomb.
- iOS/Safari long press nem hozhat létre natív kék szövegkijelölést a naptárban vagy az azt követően megnyíló modálon.
- A jobb alsó fix `+` gyorsfoglalás megmarad.

## Foglalási ablak
- Az egyszeri és ismétlődő foglalás ugyanabból az ablakból indul.
- Ismétlődési lehetőség csak olyan helyiségnél aktív, amelyhez a backend `list_repeatable_rooms` alapján az adott user jogosult.
- Az ismétlődés gyakorisága: napi, heti, kétheti, havi.
- A sorozat ugyanebben az ablakban lezárható alkalmak száma vagy végdátum alapján, Skedda-szerű választással.
- Az ismétlődő foglalás továbbra is a meglévő `create_booking_series` backend folyamatot használja; az üzleti és jogosultsági szabályokat a UI nem írja felül.
- Normál szobáknál a használat mindig Egyéni, ezért nincs Egyéni/Csoportos választó.
- Egyéni/Csoportos választó csak Tréningteremnél jelenik meg.
- A Tréningterem helyiségnév mobil fejlécben csak egyszer jelenhet meg.

## Mobil navigáció
- Kompakt A-Hely + hamburger menü használatos.
- Menüpont kiválasztásakor a hamburger panel azonnal bezár.
- Route-váltás után sem maradhat nyitva.

## Regresszióvédelem

A fenti működések már stagingen kialakított és elfogadott viselkedések. Mobil naptárt, CSS-t, foglalási modált vagy navigációt érintő refaktor során külön ellenőrizni kell, hogy egyik sem tűnt el és nem romlott vissza.

A cél a Skedda használati logikájának követése, nem a szolgáltatás teljes vizuális másolata vagy fölösleges funkcióinak átvétele.
