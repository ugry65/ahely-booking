# Kiadási és környezeti állapot – 2026-10-29

Ez dátumozott állapotjelentés, nem új production-módosítási engedély.
A felhasználó 2026-10-29-én megerősítette: az éles rendszer jól működik.

## Tréningterem csoportos előrefoglalás – éles

A [#317](https://github.com/ugry65/ahely-booking/pull/317) fejlesztés és az elfogadott staging UAT után a [#318](https://github.com/ugry65/ahely-booking/pull/318) 2026-10-28-án productionbe került.
Normál felhasználó csoportos Tréningterem-foglalása fix 180 napra előre engedett,
az általános és felhasználói override-tól függetlenül. Egyéni használat legfeljebb
10 nap, szigorúbb felhasználói limit esetén annál kevesebb. Az admin és az egyéb
jogosultsági/sorozat-/átfedési szabályok változatlanok.

| Bizonyíték | Rögzített érték |
| --- | --- |
| Tesztelt main/staging SHA | `45e765ae6c515c677d1d24f6b836f9141e4ffb27` |
| Production merge SHA | `caf98c8c483e4d25022e549fb2d9521e8ff1b80c` |
| Közös fájlfa | `ceda4601454bf76f5ea73328756be4ead3676a20` |
| Staging deployment | `dpl_EU8xScTzJvfk1FB8cgJJbRTJGPUN`, READY |
| Production deployment | `dpl_CwRSk4Mn2dUA6PLLkAneKvRfvUEP`, READY |
| Éles domain | `foglalas.a-hely.com` |
| Alkalmazott production migráció | `20261028151000_training_group_180_day_limit` |
| Új függvénytörzs MD5 | `1f81f5938e5aefdf195f0f38ab4600c4` |
| Változatlan függvény-ACL | `{postgres=X/postgres}` |

A korábbi hibás staging migration version rendezve: a helyes `20261028151000`
szerepel, a `20261028160455` nem. A korábbi staging SQL-bájtegyezés külön
bizonyíték; a CLI által tárolt statements reprezentációját nem szabad a teljes
Git-fájl hash-ével automatikusan azonosnak tekinteni.

## Mentés, restore és DB-first kiadás

- [Kézi backup, run40732025262](https://github.com/ugry65/ahely-booking/actions/runs/40732025262): SUCCESS, Google Drive és Backblaze B2 visszaolvasás/ellenőrzés. Artifact: `ahely-booking-production_20261028T170354Z_a8d8f2ab2004.tar.gz.age`.
- A production ágas korábbi indítást az Environment ágvédelem elutasította; támogatott main fallback külön felhasználói engedéllyel történt, védelem átállítása nélkül.
- [Drill backup, run40732293302](https://github.com/ugry65/ahely-booking/actions/runs/40732293302): kétcélos SUCCESS; artifact `ahely-booking-production-drill_20261028T170528Z_a8d8f2ab2004.tar.gz.age`.
- A korábbi restore az `auth.one_time_tokens.expires_at` hiánya miatt megállt. [#319](https://github.com/ugry65/ahely-booking/pull/319) csak az izolált restore-célsémát egészítette ki; nem dobott el tokenadatot és nem módosított hosted Auth sémát. Külső Claude APPROVE, main merge `6a05f276f50abbd6545a93af64b136443b51f3bf`.
- [Teljes izolált restore, run40738525124](https://github.com/ugry65/ahely-booking/actions/runs/40738525124): SUCCESS azonos drill artifactból, két tároló, visszafejtés, belső checksumok és manifest-kontrollszámok ellenőrizve. Ez az adott mentés visszaállíthatósági bizonyítéka.
- A 17 történeti migration-version eltérésnél az általános dry-run biztonságosan leállt. [#320](https://github.com/ugry65/ahely-booking/pull/320) review-zott célzott kiadási útja kizárólag az egy új migrációt alkalmazta; nincs történeti replay vagy tömeges history repair.
- [Célzott dry-run, run40743754476](https://github.com/ugry65/ahely-booking/actions/runs/40743754476): SUCCESS. [Apply, run40744050392](https://github.com/ugry65/ahely-booking/actions/runs/40744050392): SUCCESS. A backup/restore hatórás frissességi kapuja a futáskor teljesült.
- [Production release gate, run40744226369](https://github.com/ugry65/ahely-booking/actions/runs/40744226369): SUCCESS. A tesztelt jelölt 319 Vitest és 897 pgTAP tesztje, valamint a concurrency integrációk sikeresek voltak.

A production history 94-ről 95 sorra nőtt; a régi 94 sor összesített hash-e változatlan:
`9d7fb2c6810f325a6a5fc6097c6d472f`. A DB-apply előtt/után az ellenőrzött táblák
teljes sorhash-e és darabszáma azonos: bookings 2499, payments 6, payment_voids 0,
monthly_settlement_periods 1, monthly_settlements 53, settlement_adjustments 0,
settlement_booking_lines 883, settlement_revisions 63. Ezek a kiadási időpont
kontrollszámai, nem az örökké elvárt aktuális darabszámok.

Éles read-only szabály-smoke: csoport 30/180 nap elfogadott, csoport 181 és egyéni 11
nap elutasított; nem hozott létre foglalást. Health HTTP 200/database=ok,
bejelentkezés nélkül `/foglalasok` HTTP 307 → `/belepes`. Az indulás utáni rövid
error/fatal naplóablak üres volt. Saját bejelentkezett production UI-UAT nem
állítható; staging projektgazdai UAT és későbbi pozitív éles visszajelzés van.

A restore-lint dokumentált legacy jelzései fennmaradtak. A külső review nem
talált célmigrációt blokkoló függőséget; ez nem teljes adatbázis-hibamentességi
nyilatkozat. A backup/restore runok ma már történeti bizonyítékok, új kiadásra
nem használhatók automatikusan friss mentésként.

## Havi elszámolási összesítő – 2026-10-27

[#314](https://github.com/ugry65/ahely-booking/pull/314) a havi zárás összesítőjét
a befizetési részletek elé helyezte. Külön látható a fennmaradó fizetendő összeg,
a befizetett összeg, a teljes havi díj és a túlfizetés. Csak frontendváltozás,
DB-migráció és pénzügyi adatírás nélkül. A [#315 production release](https://github.com/ugry65/ahely-booking/pull/315)
merged; független APPROVE, CI és felhasználói jóváhagyás a PR-ban rögzítve.
Korabeli main `103b91a12d45bcf3a52f7e1e38712f46227778c9`, production
`30d165d20b0cdba2dc2b85f45f62918fd1af6561`; azóta a #318 release felülírta mint
aktuális deployment-baseline-t, a funkció megmaradt.

## Mai staging Auth-javítás és környezeti audit

A [#238](https://github.com/ugry65/ahely-booking/issues/238) hibánál a hosted
staging recovery sablon `{{ .RedirectTo }}&token_hash=...` linkje 404-et okozott.
2026-10-29-én kizárólag stagingen átállítva:
`{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery`.
Site URL helyes staging origin, mentés és újratöltés után a javítás megmaradt.
Ez megegyezik az élő production sablon linkképzésével; a levélszöveg különbözik.
A felhasználó visszaigazolta, hogy az oldal megnyílik. A következő jelszómentési
hiba Auth-kódja `same_password`: az újként megadott jelszó megegyezett a régivel,
nem jelszóerősségi vagy404 probléma. Új, különböző jelszóval teljes sikeres
end-to-end folyamat még nincs visszaigazolva. Jelszó vagy token nem kerül ide.

Kód/fájlfa és mind a 10 app_settings egyezik. A vizsgált Auth email-követelmények
és 86400 másodperces linkérvényesség egyeznek. Staging booking email `capture`,
production `disabled`; ez nem Auth-email kapcsoló. A külön domainek,
adatbáziscélok és kulcsok szükséges környezeti eltérések.

A public séma 1036 objektuma pontosan egyezik; a 21 közös függvény szövegeltérése
komment/formázás/opcionális AS alias/egy nem használt deklaráció normalizálása
után eltűnik. Ez nem teljes szemantikai bizonyítás. Staging 1064, production 1061
objektum. Stagingen5 történeti csoportos díjat őrző legacy oszlop és automatikus
5000 Ft-os default trigger maradt; productionben nincs. A történeti díjak miatt
az oszlopot nem szabad egyszerűen törölni. A [#321](https://github.com/ugry65/ahely-booking/pull/321)
csak a default trigger eltávolítását javasolja, adatátírás nélkül. Exact head
`531f5140f690231902728548fa01d2c6224539c6`, minden CI SUCCESS, független Claude-review
folyamatban. **Még nincs staging apply vagy merge; production módosítás tiltott.**
A két production-only történeti import RPC és a megmaradó legacy admin RPC
különbsége dokumentált; nem állítható teljes séma/RPC-paritás.

Teljes SMTP-, valamennyi Auth- és managed séma-egyezés nincs igazolva. Az
ellenőrzött scope az alkalmazás public sémája és a felsorolt beállítások.
