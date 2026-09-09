# Anti-pause review scope

Review fókusz:

- endpoint csak read-only DB műveletet végez;
- `CRON_SECRET` nélkül fail-closed;
- válasz nem szivárogtat adatot;
- Vercel Cron csak production deploymentben aktiválódik;
- napi 4 futás elegendő tartalékot ad a 7 napos low-activity pause kockázathoz;
- production aktiválás külön jóváhagyás nélkül tilos.
