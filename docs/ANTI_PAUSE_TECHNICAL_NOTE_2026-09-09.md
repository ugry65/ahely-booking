# Supabase Free anti-pause technikai döntés – 2026-09-09

A production projekt költségbaseline-ja továbbra is Supabase Free. Az automatikus pause kockázatot nem előfizetéssel, hanem legitim alkalmazásoldali aktivitással kezeljük.

A Supabase dokumentációja szerint a Free projekt alacsony aktivitás esetén 7 napos ablakban pause-ra jelölhető, és tipikusan napi néhány user database request elegendő a pause elkerüléséhez. A választott megoldás ezért napi 4 darab, 6 óránkénti, valódi read-only adatbázislekérdezés Vercel Cronból.

A megoldás biztonsági elvei:

- cron endpoint nem publikus health-adatforrás, Bearer `CRON_SECRET` védi;
- a válasz nem tartalmaz adatbázisrekordot, személyes adatot vagy technikai hibadetailt;
- DB-művelet kizárólag SELECT;
- write művelet nincs, tehát nem keletkezik mesterséges üzleti/audit adat;
- 503-as válasz valódi DB-elérhetőségi hibát jelez;
- production aktiválás külön jóváhagyáshoz kötött.

Kapcsolódó runbook: `docs/PRODUCTION_ANTI_PAUSE_RUNBOOK.md`.
Kapcsolódó issue: #114.