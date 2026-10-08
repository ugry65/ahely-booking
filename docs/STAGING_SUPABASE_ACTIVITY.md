# Staging Supabase aktivitásellenőrzés – 2026-10-08

Kapcsolódó issue: #282. Kizárólag staging; production változtatás nem része a feladatnak.

## Döntés és korlát

A meglévő, dinamikus staging `GET /api/health` végpontot használjuk újra.
A route publishable kulccsal az `anon` szerepkörben hívja a
`public.system_health_check()` SECURITY INVOKER / STABLE RPC-t, amely
`select true;` SQL-t hajt végre. Ez tényleges PostgREST → PostgreSQL kérés,
de nem olvas üzleti táblát és nem ír adatot. Új credential, szerepkör,
sémamigráció vagy mesterséges booking nem szükséges.

A Supabase [hivatalos pause-leírása](https://supabase.com/docs/guides/platform/free-project-pausing)
szerint az elmúlt hét elégtelen user DB aktivitása vezethet Free projekt
szüneteltetéséhez; napi néhány kérés általában elegendő, de nincs garantált
küszöb vagy erre az RPC-re vonatkozó garancia. Ez kockázatcsökkentés,
nem pause-mentességi vállalás. Nem helyettesít backupot.

## Ütemezés és izoláció

- Workflow: `.github/workflows/staging-supabase-activity.yml`.
- Napi 03:17, 09:17, 15:17, 21:17; `Europe/Budapest`, téli/nyári váltással.
- A 03:17 nem ismétlődő/kihagyott helyi időpont a budapesti DST-váltáskor.
- Manuális indítás: Actions → Staging Supabase activity → Run workflow → main.
- Az élő job kizárólag ebben a repositoryban, mainen, schedule/dispatch eseménynél fut.
- PR-en csak offline tesztek futnak; nincs environment vagy secret a tesztjobban.
- Kizárólag `contents: read` GitHub token, checkout credential persist nélkül.
- Az élő job staging environmentből egyetlen secretet használ:
  `STAGING_ACTIVITY_HEARTBEAT_URL`. Nem DB-kapcsolat vagy Supabase-kulcs.
- Nincs production secret-hivatkozás, production endpoint vagy production environment.
- Fix HTTPS staging cél; nincs tetszőleges URL input, átirányítás nem követhető.
- 25 másodperces HTTP deadline; HTTP 200 + JSON + no-store + pontos DB success szükséges.
- SQL/HTTP hibatartalom és heartbeat cím nem kerül a script naplójába.

A [GitHub schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
késhet, el is maradhat; publikus repositoryban 60 nap repository-inaktivitás
után automatikusan letiltható. A kimaradás-monitor ezért szükséges.
Main merge automatikusan a külön staging Vercel projektet telepíti;
production továbbra is külön main → production PR-t igényel.

## Heartbeat és riasztás

A meglévő Healthchecks.io fiókban külön `A-Hely staging activity` monitor:
6 órás periódus, 2 órás grace, meglévő email integráció
`backupahely@gmail.com`. Létrehozáskor 16 szabad monitorhely volt;
új előfizetés vagy költség nem keletkezett. A négy production backup monitorhoz
és értesítési beállításaikhoz nem nyúltunk.

- DB/API hiba: script piros Actions futás és `/fail` heartbeat, amely Down állapotot jelez.
- DB success: success heartbeat; a következő siker Up recoveryt jelez.
- Heartbeat küldési hiba/runner leállás/kimaradt schedule: nincs sikeres ping;
  a monitor az utolsó siker után 8 órával Down állapotba kerül és értesít.
- A /fail csak az első probe után küldhető; csak a jóváhagyott hc-ping.com UUID formátum elfogadott.
- Supabase pause: a következő ellenőrzés hibája ugyanezt az utat használja.
  A Supabase külön figyelmeztető és pause-megerősítő emailt is küld a projekt tulajdonosának.
- GitHub piros futás önmagában nem garantált email: a felhasználói Actions értesítési
  beállításoktól/actor szereptől függ, ezért nem ez az elsődleges riasztási csatorna.
- A Healthchecks email integráció bekapcsolása és a monitor eseménye bizonyítja
  a küldési konfigurációt, de a tényleges postaládába érkezést külön kell igazolni.

## Ellenőrzés és visszaállítás

1. `node --test scripts/test-staging-activity.mjs` – 14 teszt: HTTP/DB hiba,
   JSON/no-store, redirect, valós fetch timeout, /fail/recovery routing,
   secretmentes hibanapló, offline PR és branch/environment guard, DST.
2. Main merge után kézi workflow, a `staging-activity` job és monitor sikerping ellenőrzése.
3. Következő scheduled futás és időpont ellenőrzése; a GitHub késése külön dokumentálandó.
4. Csak a staging monitoron kontrollált failure/recovery teszt; production monitor
   nem tesztelhető vagy módosítható e feladatban.
5. Leállítás: kizárólag a Staging Supabase activity workflow letiltása. Nem igényel
   DB rollbacket; a monitor szükség esetén külön szüneteltethető.

## 2026-10-08 előzetes élő bizonyíték

- Main SHA: `b0c3d1e932db55a28c385d3ab52c4b995c4aff22`.
- Production SHA (csak ref olvasás): `c0c7158f86946fffc1801eec348e27aa908cf56a`.
- Staging deployment: `dpl_4tPGoTc8mBNGSbE36tek2dN3rWXh`, READY, main SHA egyezik.
- Vercel projekt: `prj_LzVgZgZBCAj4zA64YoYED3XkLGKW`.
- Staging Vercel `NEXT_PUBLIC_SUPABASE_URL`: `https://fvwapntzhavhgazeflri.supabase.co`.
- Staging Supabase: ACTIVE_HEALTHY; élő function definition `select true;`, anon EXECUTE.
- Staging HTTP smoke: 200, database ok, Cache-Control no-store.
- Lokális célzott tesztek 14/14 PASS; meglévő alkalmazás unit tesztek 215/215 PASS,
  typecheck PASS; release-evidence --release PASS (nem production deploy-engedély).
Az alábbi bevezetési jegyzőkönyv a merge utáni végleges eredményeket rögzíti.

## Bevezetési jegyzőkönyv – 2026-10-08

**Implementáció és kézi működésellenőrzés kész; a megfigyelési kapuk még nyitottak.**

- Implementáció: [PR #283](https://github.com/ugry65/ahely-booking/pull/283), mainbe merge-elve.
  Bevezetett main SHA: `035345fde6f646e1b75930171f57b4904faaf3c2`.
- Staging Vercel deployment: `dpl_6eWAJQCM9NJmjr1gS4kbtr58wkfz`, READY,
  a fenti main SHA-val. Merge utáni staging HTTP smoke: 200, database ok, no-store.
- [Kézi Actions futás #37793493333](https://github.com/ugry65/ahely-booking/actions/runs/37793493333):
  main / workflow_dispatch, 2026-10-08 16:33:50–16:34:20 Europe/Budapest;
  offline tesztjob és élő staging job SUCCESS. Napló: `Staging database activity probe passed.`
- Tesztek: célzott 14/14 és alkalmazás 215/215 PASS; typecheck és
  release-evidence ellenőrzés PASS. PR és main CI application-checks /
  evidence-consistency PASS; a PR-en az élő staging job szándékosan nem fut.
- Kódreview és javítások dokumentálva a PR-ben. Ez saját kódreview volt;
  független Claude-review nem történt. Foglalási, pénzügyi vagy jogosultsági kód nem változott.
- A külön staging Healthchecks monitoron kontrollált `/fail` → sikerping teszt
  Down → Up eseményt eredményezett. A teszt nem állította le az alkalmazást vagy a DB-t.
  Az email integráció bekapcsolva; postaládába érkezés még nem igazolt.
- Production ref a bevezetés után is
  `c0c7158f86946fffc1801eec348e27aa908cf56a`; production alkalmazás,
  DB, workflow és environment nem módosult. Az új probe csak a meglévő,
  üzleti adatot nem író RPC-t hívja; üzleti adatot módosító műveletet nem végeztünk.
- [Issue #282](https://github.com/ugry65/ahely-booking/issues/282) nyitva marad
  a következő ellenőrzések bizonyítékának rögzítésére.

### Még ellenőrizendő

1. Az első tényleges scheduled futás: bevezetéskor még nem volt megfigyelhető;
   a következő tervezett időpont 2026-10-08 21:17 Europe/Budapest.
2. Healthchecks hiba-/helyreállítási értesítés tényleges megérkezése
   a `backupahely@gmail.com` postaládába.
3. Legalább hét teljes nap automatikus működés és Supabase státusz megfigyelése.
   A szüneteltetés elkerülése előre nem garantálható.

## Legalább hétnapos megfigyelés

A bevezetési kézi siker és első scheduled siker után számítsunk hét teljes napot.
Ha az első scheduled siker 2026-10-08 21:17-kor történik, a legkorábbi
hétnapos felülvizsgálat 2026-10-15 21:17 után esedékes (Europe/Budapest).
Későbbi első siker esetén a felülvizsgálat időpontja is későbbre kerül.
Az issue maradjon nyitva az ellenőrzéshez.

Ellenőrizni kell: napi négy Actions futás eredménye/hiányai; monitor pingtörténet
és Down/Up események; Supabase ACTIVE_HEALTHY státusz; friss inactivity warning
és pause email hiánya/jelenléte. A korábbi email megmaradása nem új figyelmeztetés.
Supabase Logs/API forgalom napi aktivitással egyeztetendő (Free logretention rövid).
Az app config megváltozásakor ismét igazolni kell, hogy a staging URL a staging DB-t használja:
a publikus health body szándékosan nem közöl project refet.
Hét problémamentes nap sem jelent hosszú távú garanciát. Új figyelmeztetés esetén
a bizonyítékokkal Supabase support egyeztetés kell; fizetős csomag csak külön döntéssel.
