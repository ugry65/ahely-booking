# Független review – #296

2026-10-13 23:33 Europe/Budapest: projektgazda kifejezetten engedélyezte külön ellenőrző ügynök használatát és sikeres review után staging telepítést. Reviewer: külön `pricing_review` ügynök; nem Claude, nem GitHub-reviewként azonosítjuk. Nem írt fájlt vagy külső állapotot.

Review verdict: **APPROVE, staging bevezetésre**, pontos-HEAD sikeres CI és célazonosítás mellett. Review HEAD `576b23c2a510050af7bdf3264335bb3a5f0e1592`, base `9b2180282f61bf847733a78d23740d7a2a131115`. Ez nem production GO.

Ellenőrzött: aktuális budapesti hónap alsó dátumhatára/null/infinity input; zárolás utáni újraellenőrzés; az authoritative close és mindkét setter közös period-lockja, publication/legacy is_closed guard az írás előtt; nincs close↔tarifa lock-ciklus; későbbi időszak és előző hónap napi feloldása megmarad; snapshot írás nincs; override priorítás/aktív admin/fix search_path/ACL/indok/audit; UI fail-closed és érvényességi dátumhoz tartozó díjelőtöltés; pgTAP valós close/snapshot hash/ACL/rollback és valódi különkapcsolatos race.

Reviewer saját futása: 14/14 célzott Vitest PASS, concurrency script bash -n PASS. Root által külön igazolt pontos-HEAD Database tests run [38468679068](https://github.com/ugry65/ahely-booking/actions/runs/38468679068): 47 pgTAP fájl, 791 teszt PASS, pricing→close központi és close→central/training race PASS. Application/evidence-consistency/isolated-reference SUCCESS. A reviewer nem végzett DB-futást és nem állította bejelentkezett UI-UAT-nak a kódellenőrzést.

Nem blokkoló észrevételek: legacy részleges is_closed hónapot a UI opennek mutathat, de DB biztonságosan tilt; training→close külön ága nem tesztelt, a központi irány és mindkét close→setter ág igen; projektkontextus EOF extra üres sor kozmetikai javítása.

## Staging baseline reconciliation külön ellenőrzése

A deploy előtti projection guard helyesen megállt: actual93 vs pinned92. Mind a 92 korábbi version/name/MD5 változatlan; az egyetlen új, már alkalmazott sor `20261001174547 / monthly_tier_include_training_group`, MD5 `a6b67fa9034780b300d8dc66d4bb4db8`.

Canonical fájl: `20261001193000_monthly_tier_include_training_group.sql`, provenance #261 / `ceeeebe`, SHA256 `88d5052606f3f19f817af03b4f3477047d26599396c17a9db80cafc982818aa5`. A teljes stored SQL a canonical fájllal bájtszinten egyezik (1756 bájt); az élő `month_normal_minutes(uuid,date,uuid,integer,boolean)` prosrc is pontosan egyezik. SECURITY DEFINER, üres search_path, anon/authenticated/service_role execute=false igazolt.

A reviewer előírása: kizárólag az actual row hozzáadása és a canonical fájl hash-pinnelt excluded_local mappingje; minden régi rekord/hash megőrzése; guard algoritmus változatlan; nincs remote history repair vagy régi SQL replay. Új projectionben kizárólag az új #295 migration lehet pending.

Follow-up review: **reconciliation diff APPROVE, nincs blocker**. A reviewer önállóan ellenőrizte a 92 történeti rekord/hash változatlanságát, az új actual row/canonical mappinget, a változatlan algoritmust, az EOF javítást és a diff-check PASS-t. Root projection:93 applied, kizárólag20261013205742 pending. A #296 staging APPROVE a kizárólag manifest/bizonyíték kiegészítéssel fennmarad; pontos-HEAD CI szükséges.
