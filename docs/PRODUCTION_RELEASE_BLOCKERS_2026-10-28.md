> **Lezárt kiadási akadályok – 2026-10-29:** A #319 javítás után a teljes izolált restore run40738525124 SUCCESS. A #320 review-zott célzott útján a dry-run run40743754476 és apply run40744050392 SUCCESS, majd #318 production release READY. Nem történt történeti replay vagy tömeges repair. Az alábbi elemzés az elhárítás előtti állapot; a legacy lint-korlátok továbbra is fennállnak. [Végső bizonyítékok](RELEASE_STATUS_2026-10-29.md).

# Production release-blocker vizsgálat – 2026-10-28

Kapcsolódó kiadás: #318; vizsgált main: `a8d8f2ab2004d3d5328fd71014f4b873121241c2`. Production: `yasrmxwjojepessivhmc`. Kizárólag olvasó SQL-lekérdezés és repository-összehasonlítás; nincs history repair vagy üzleti adatírás.

## Restore javítás

A #197 kézi backup és a #4 production backup drill kétcélos ellenőrzése sikeres. A #8 izolált restore megállt a nem üres `auth.one_time_tokens` COPY blokk `expires_at` oszlopán. A production oszlop ellenőrzött típusa `timestamp with time zone`, nullable, default nélkül. A hivatalos Supabase Auth `05d9aec` commit `20260831180000_add_expires_at_to_one_time_tokens.up.sql` migrációja ugyanezt az oszlopot adja hozzá.

A javítás kizárólag az újonnan indított Docker restore adatbázisban készíti elő az oszlopot: a schema preflight előtt és a helyi reset után is. A meglévő oszlop típusát/nullability/defaultját ellenőrzi, eltérésnél leáll. A dump és a nem üres COPY blokk változatlan; nincs oszlop- vagy soreldobás, és az általános kompatibilitásvédelmet nem lazítjuk. A hosted Auth migration ledgerhez nem nyúlunk.

Hivatalos forrás: https://github.com/supabase/auth/commit/05d9aec . A kód létezése nem bizonyít sikeres teljes restore-t: független review, zöld regressziós CI, main merge és ugyanazon immutable artifact teljes izolált újrapróbája szükséges. A jelen PR önmagában NEM production GO.

## A 17 távoli migration version

A #12 production dry-run hiba oka az alábbi 17 remote-only verzió. A neveket és a `md5(array_to_string(statements, ''))` értékeket a production ledgerből olvastuk. A név önmagában nem egyezési bizonyíték.

| Production verzió | Repository fájl | Remote SQL MD5 | Bizonyíték |
| --- | --- | --- | --- |
| `20260926102513` | `20260926103000_move_btree_gist_out_of_public.sql` | `998f5b33b7b5e48b49fc0c1e7bc4f782` | PostgreSQL lexikai tokenek egyeznek; csak komment/whitespace eltérés |
| `20260927142516` | `20260927120000_multi_customer_allbooked_batch.sql` | `3d199e0f279f134940dd562025021634` | PostgreSQL lexikai tokenek egyeznek; csak komment/whitespace eltérés |
| `20260927142523` | `20260927124500_harden_allbooked_auth_compensation.sql` | `abb49b716597fd92c53acd4daba8678d` | Bájtszintű egyezés |
| `20260927184557` | `20260927190000_admin_user_email_change.sql` | `d3904b6342201a5ad54a8b738d8ad4e4` | Bájtszintű egyezés |
| `20260927184605` | `20260927193000_monthly_summary_pricing_breakdown.sql` | `cdc9e59b35107f0e2a9d6f8d290335cd` | Bájtszintű egyezés |
| `20260927184610` | `20260927194000_allow_retroactive_user_hourly_rate.sql` | `d53f99e9bf3f379548789a5621e4658a` | Bájtszintű egyezés |
| `20260927184615` | `20260927201500_email_finalize_accept_auth_profile_sync.sql` | `2b82ae401fb9b69a41a8e3f57082db47` | Bájtszintű egyezés |
| `20260927184621` | `20260927210000_email_change_explicit_actor.sql` | `6b4730449228bc70cca0c84379efd910` | Bájtszintű egyezés |
| `20260927184627` | `20260927213000_restore_future_only_global_pricing.sql` | `896059c02f1da934cb31f02aeb31c76d` | Bájtszintű egyezés |
| `20260928145255` | `20260928162000_user_calendar_color_self_service.sql` | `416feb6d39fc1cc9ecd0e61b8e083a9b` | PostgreSQL lexikai tokenek egyeznek; csak komment/whitespace eltérés |
| `20260928145308` | `20260928165000_allow_own_calendar_color_read.sql` | `d077777cdd2ec6d558af7d992c64f9b3` | PostgreSQL lexikai tokenek egyeznek; csak komment/whitespace eltérés |
| `20260930212347` | `20260929182024_monthly_settlement_publication.sql` | `d8e3ffccb35576bd21007aac3eab864a` | Nem azonos; külön review szükséges |
| `20261001175625` | `20261001193000_monthly_tier_include_training_group.sql` | `a6b67fa9034780b300d8dc66d4bb4db8` | Bájtszintű egyezés |
| `20261014110645` | `20261013205742_allow_current_open_month_global_pricing.sql` | `c39cffa328a78960f9cca30b398333d7` | Bájtszintű egyezés |
| `20261014214018` | `20261014165936_booking_payments.sql` | `2f72b1361b6973cf500303c08ecec0f0` | Bájtszintű egyezés |
| `20261014214025` | `20261014205348_admin_open_month_booking_correction.sql` | `a11ce7ccceb4d31f8303c338817ec5f7` | Bájtszintű egyezés |
| `20261019211049` | `20261019200553_partial_booking_cancellation.sql` | `bd1fa03fe3c472dc56ca271c678a8d79` | Bájtszintű egyezés |

A négy lexikai összevetés pglast 8.7 PostgreSQL scannerrel készült, kommentek és whitespace nélkül, a string literálok megőrzésével; a dollar-quoted függvénytörzs külön tokenizálva. Ez szűkebb bizonyíték, mint a teljes telepített sémaegyezés.

A `monthly_settlement_publication` helyi és távoli változata eltérő formázás mellett opcionális SQL-alias `AS` eltérést és legalább egy kihagyott `v_closed_at` PL/pgSQL deklarációt tartalmaz. Mindkét változat 11 PL/pgSQL függvényként parse-olható, de a teljes AST nem azonos. Ezt NEM minősítjük bájtszintű vagy teljes szemantikai egyezésnek. A későbbi, azonos SQL-ű `booking_payments` migráció felülír egyes érintett függvényeket; ez nem rendezi automatikusan a történeti ledger egészét.

## Következő kiadási lépések

1. Restore javítás független review és CI; merge csak a szükséges review után.
2. Ugyanazon drill artifact teljes izolált restore, az adatkontrollokkal együtt. Új FAIL esetén production továbbra is tiltott.
3. A fennmaradó history-eltérés és a local-only migrációk tételes egyeztetése. A fenti audit nem jogosít `repair --status reverted` vagy `db push --include-all` futtatására.
4. Csak az új `20261028151000_training_group_180_day_limit` migrációt alkalmazó, eredeti verziót megőrző eljárás ellenőrzése; meglévő migrációk újrajátszása tilos.
5. Friss #318 main SHA/deployment/UAT és GitHub release gate, DB-first alkalmazás, majd production deploy és adatmegőrzési/smoke ellenőrzések.

Bizonyítékok: [backup #197](https://github.com/ugry65/ahely-booking/actions/runs/40732025262), [drill backup #4](https://github.com/ugry65/ahely-booking/actions/runs/40732293302), [restore #8 FAIL](https://github.com/ugry65/ahely-booking/actions/runs/40732892339), [dry-run #12 FAIL](https://github.com/ugry65/ahely-booking/actions/runs/40733213275).

## Kiegészítő szerkezeti összevetés – 2026-10-28

A `monthly_settlement_publication` két változatát pglast 8.7 PostgreSQL SQL- és PL/pgSQL-parserrel is összevetettük. Az SQL AST-k a forráspozíciók eltávolítása és a külön vizsgált függvénytörzsek helyettesítése után azonosak. Mind a 11 PL/pgSQL-függvény AST-je azonos, ha a forrássorszámokat/formázást normalizáljuk és a helyi `v_closed_at timestamptz` deklarációt külön kezeljük. A változó helyben pontosan egyszer, kizárólag deklarációként fordul elő; a távoli változatban nincs jelen. A beágyazott SQL-ek parseres összevetése az opcionális `AS` alias-kulcsszót is kezeli; a nem önálló SQL-ként parse-olható értékadások lexikai tokenjeit változatlan literálokkal hasonlítottuk össze.

Ezzel a történeti forrásszövegekben **nem találtunk végrehajtási logikabeli eltérést**: 12 bájtszinten azonos, 4 csak whitespace/komment eltérésű, 1 szerkezetileg azonos az egyetlen nem használt deklaráció kivételével. Ez nem azonos a teljes aktuális production séma auditjával, nem független review, és nem engedély a ledger automatikus átírására vagy történeti SQL újrafuttatására.
