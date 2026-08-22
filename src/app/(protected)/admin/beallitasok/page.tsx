import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { saveAdvanceBookingLimits } from "./actions";

type SettingRow = { key: string; value: number };

function numberValue(rows: SettingRow[], key: string) {
  const row = rows.find((item) => item.key === key);
  return typeof row?.value === "number" && Number.isInteger(row.value) && row.value >= 0 ? row.value : null;
}

export default async function AdminSettingsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("app_settings")
    .select("key,value")
    .in("key", ["default_advance_booking_days", "training_room_advance_days"])
    .returns<SettingRow[]>();

  const rows = data ?? [];
  const defaultDays = numberValue(rows, "default_advance_booking_days");
  const trainingDays = numberValue(rows, "training_room_advance_days");
  const invalidSettings = error || defaultDays === null || trainingDays === null;

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Beállítások</h1><p className="muted">Központi foglalási paraméterek.</p></div></header>
    {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
    {params.uzenet ? <p className="message success" role="status">{params.uzenet}</p> : null}
    {invalidSettings ? <p className="message error" role="alert">Az előrefoglalási beállítások hiányoznak vagy hibásak. A foglalási backend ilyen állapotban fail-closed módon elutasítja a normál user foglalását.</p> : null}

    <section className="card wide-card stack">
      <div><h2>Előrefoglalási limitek</h2><p className="muted">A normál helyiségek és a Tréningterem limitje külön állítható. Az admin foglalásaira ezek a normál user limitek nem vonatkoznak.</p></div>
      {!invalidSettings ? <form action={saveAdvanceBookingLimits} className="admin-editor-row">
        <label>Normál helyiségek<input name="defaultDays" type="number" min="0" step="1" required defaultValue={defaultDays} /><span className="muted form-help">Nap. Jelenlegi alapérték: 90 nap.</span></label>
        <label>Tréningterem<input name="trainingDays" type="number" min="0" step="1" required defaultValue={trainingDays} /><span className="muted form-help">Nap. Jelenlegi alapérték: 10 nap.</span></label>
        <button type="submit">Limitek mentése</button>
      </form> : null}
      <p className="muted form-help">A módosítás admin-only és auditált. A backend minden egyszeri és ismétlődő foglalásnál az aktuális értékeket használja.</p>
    </section>
  </section>;
}
