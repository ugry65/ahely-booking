# Célzott production migráció – #316

## Bizonyíték és hatókör

A #319 független Claude-review-ja a `f28025dab75348cd487d8b4b06a82216a9c91243` headet APPROVE-nak minősítette. A projektgazda által csatolt review SHA-256: `d1726377ae1cf83ce19b47834ab571eaa8892abc0dff829d4f8943ebb21bfc1f`; külső review, nem GitHub review submission. A javítás mainbe került: `6a05f276f50abbd6545a93af64b136443b51f3bf`.

A [#9 teljes izolált restore](https://github.com/ugry65/ahely-booking/actions/runs/40738525124) SUCCESS. Ugyanazt az immutable `ahely-booking-production-drill_20261028T170528Z_a8d8f2ab2004.tar.gz.age` artifactot töltötte le mindkét célhelyről, ellenőrizte/visszafejtette, és helyreállította az izolált célban. A manifest kontrollszámai egyeztek: 2499 foglalás, 53 monthly settlement, 63 revision, 883 settlement booking line, 3533 auditrekord, 94 migration-history sor. A kontrollszámok az adott mentési időpontra és a manifestben felsorolt táblákra vonatkoznak; nem minden táblára külön sorhash-bizonyíték.

A restore SQL-lint kimenete több error szintű jelzést is tartalmazott, bár a CLI nullával tért vissza. Ezeket a SUCCESS badge nem oldja fel. Read-only production ellenőrzés szerint `admin_close_monthly_settlement` csak postgres számára futtatható, a `resolve_booking_applied_rate` és `cancel_booking_parts` hiányzó legacy oszlopra jelzett dinamikus SQL-je oszloplétezés-vizsgálat mögött van. További legacy `admin_create_booking_with_group_rate`, `admin_set_booking_series_group_rate`, `get_my_monthly_pricing` lintjelzések fennmaradnak; az alkalmazás src fájljaiban ezekre közvetlen hívást nem találtunk. Ez nem teljes elérhetőségi audit, és a jelen változtatás nem javít vagy aktivál pénzügyi/legacy RPC-ket.

## Miért célzott eljárás?

A meglévő általános deploy dry-run 17 eltérő történeti version miatt leáll. A történeti SQL újrajátszása és a ledger tömeges javítása tilos. A célzott eljárás külön, privát ideiglenes CLI workdirben a ténylegesen már alkalmazott history-fájlokat tölti le a dokumentált `supabase migration fetch --db-url` paranccsal, majd csak az eredeti `20261028151000_training_group_180_day_limit.sql` fájlt adja hozzá.

CLI 2.116.0 `migration fetch --help` és `db push --help` ellenőrizve. Hivatalos referencia: https://supabase.com/docs/reference/cli/supabase-migration-list . A fetch nem repair. A push `--skip-vault` kapcsolót használ; nincs `--include-all`, roles vagy seed alkalmazás. A historyból letöltött korábbi SQL-ek nem lehetnek pending állapotban.

## Ellenőrzések

- Csak kézi main workflow, meglévő production Environment védelemmel és közös production-database-deploy concurrency csoporttal.
- Külön dry-run alapértelmezés. Deploy csak `PRODUCTION-20261028151000` megerősítéssel.
- Sikeres kézi backup #197 és restore #9 API-ellenőrzése; mindkettő legfeljebb 6 órás lehet. Ezt követően az eljárás felülvizsgálatot/friss bizonyítékot igényel.
- A jóváhagyott migration teljes SHA-256 hash-e rögzített; módosult SQL elutasítva.
- A 94 történeti history-sor verzió/név/tárolt-SQL MD5 összesített hash-e rögzített: `9d7fb2c6810f325a6a5fc6097c6d472f`. Ez változásérzékelő, nem a migrációk szemantikai helyességének bizonyítéka.
- A production eredeti `assert_booking_request` függvénytörzs MD5-je és ACL-je előzetesen egyezzen a read-only megfigyeléssel; a célmigráció még ne szerepeljen más version alatt sem.
- A fetched fájlok verzióhalmaza pontosan a remote 94 verzió legyen. A dry-run kizárólag az új fájlt sorolhatja fel; más régi SQL megjelenése leállást okoz.
- Apply előtt újraellenőrizzük a historyt és függvényt. Apply után a régi 94 history-sor hash-e változatlan, az új sor eredeti verzióval/névvel pontosan egyszer létezik, az új függvénytörzs és a változatlan ACL egyezik.

Ez nem írja át a régi ledger-sorokat és nem jelöl régi migrációt reverted/applied státuszúnak. A normál CLI az egyetlen új migráció valódi alkalmazásakor rögzíti annak eredeti verzióját.

## Kiadási kapu és korlátok

A workflow új, review-köteles production alkalmazási út. Független review és zöld CI nélkül nem merge-elhető/futtatható deploy módban. A szintetikus orchestration teszt az eltérő historyt/függvényt, replayt, hiányos fetch-et, többfájlos tervet, hibás megerősítést és feature ágat is elutasíttatja; ez nem helyettesíti a valós production dry-runt.

Review és main merge után először dry-run, annak tételes ellenőrzése, majd a még friss backup/restore bizonyítékkal külön deploy szükséges. Csak utána folytatható #318: aktuális main SHA/staging deployment/UAT egyeztetés, GitHub release gate, alkalmazásdeploy, health/authguard és célzott adatmegőrzési ellenőrzés. Az ismert lintjelzések relevanciáját a kiadási döntésben külön kell értékelni. A jelen PR nem production GO.
