import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { setCentralPricing, setTrainingRoomRate } from "./actions";

type Rule = { rule_type: "central_tier" | "training_room"; rule_id: string; min_minutes: number | null; max_minutes: number | null; room_name: string | null; use_type: "individual" | "group" | null; hourly_rate_huf: number; valid_from: string; valid_to: string | null };
function huf(value: number) { return new Intl.NumberFormat("hu-HU").format(value) + " Ft/óra"; }
function period(rule: Rule) { return `${rule.valid_from} – ${rule.valid_to ?? "folyamatos"}`; }
function nextDay() {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date()).map((part) => [part.type, part.value]));
  const date = new Date(Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day) + 1));
  return date.toISOString().slice(0, 10);
}

export default async function PricingAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_list_pricing_rules");
  const rules = (data ?? []) as unknown as Rule[];
  const central = rules.filter((rule) => rule.rule_type === "central_tier");
  const training = rules.filter((rule) => rule.rule_type === "training_room");
  const latestCentralDate = central.reduce<string | null>((latest, rule) => latest === null || rule.valid_from > latest ? rule.valid_from : latest, null);
  const latestCentral = central.filter((rule) => rule.valid_from === latestCentralDate);
  const latestCentralRate = (minMinutes: number) => latestCentral.find((rule) => rule.min_minutes === minMinutes)?.hourly_rate_huf;
  const latestTrainingRate = training[0]?.hourly_rate_huf;
  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Díjszabás</h1><p className="muted">Időben verziózott központi és Tréningterem-díjak. A korábbi időszakok nem íródnak át.</p></div></header>
    {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
    {error ? <p className="message error" role="alert">A díjszabás betöltése nem sikerült.</p> : null}
    <section className="card wide-card stack"><h2>Központi havi sávos díjak</h2><p className="muted">Nem progresszív számítás: a teljes havi normál óraszám egy sáv óradíját választja.</p>
      <div style={{ overflowX: "auto" }}><table className="admin-table"><thead><tr><th>Sáv</th><th>Óradíj</th><th>Érvényesség</th></tr></thead><tbody>{central.map((rule) => <tr key={rule.rule_id}><td>{rule.max_minutes === 900 ? "1–15 óra" : rule.max_minutes === 3600 ? "15 óra felett–60 óráig" : "60 óra felett"}</td><td>{huf(rule.hourly_rate_huf)}</td><td>{period(rule)}</td></tr>)}</tbody></table></div>
      <form action={setCentralPricing} className="admin-editor-row"><label>Érvényes ettől<input type="date" name="validFrom" min={nextDay()} defaultValue={nextDay()} required /></label><label>1–15 óra<input type="number" name="rate1To15" min="0" step="1" defaultValue={latestCentralRate(60) ?? 2500} required /></label><label>&gt;15–60 óra<input type="number" name="rateOver15To60" min="0" step="1" defaultValue={latestCentralRate(901) ?? 1900} required /></label><label>&gt;60 óra<input type="number" name="rateOver60" min="0" step="1" defaultValue={latestCentralRate(3601) ?? 1700} required /></label><label>Indok<input name="reason" maxLength={300} required placeholder="Miért változik?" /></label><button type="submit">Új díjszabás mentése</button></form>
    </section>
    <section className="card wide-card stack"><h2>Tréningterem csoportos alapdíj</h2><p className="muted">Az egyéni Tréningterem-használat normál díjazású. A csoportos alapdíjat a booking- vagy user-szintű egyedi óradíj felülírhatja.</p>
      <div style={{ overflowX: "auto" }}><table className="admin-table"><thead><tr><th>Helyiség</th><th>Használat</th><th>Óradíj</th><th>Érvényesség</th></tr></thead><tbody>{training.map((rule) => <tr key={rule.rule_id}><td>{rule.room_name}</td><td>Csoportos</td><td>{huf(rule.hourly_rate_huf)}</td><td>{period(rule)}</td></tr>)}</tbody></table></div>
      <form action={setTrainingRoomRate} className="admin-editor-row compact"><label>Érvényes ettől<input type="date" name="validFrom" min={nextDay()} defaultValue={nextDay()} required /></label><label>Óradíj<input type="number" name="hourlyRate" min="0" step="1" defaultValue={latestTrainingRate ?? 5000} required /></label><label>Indok<input name="reason" maxLength={300} required placeholder="Miért változik?" /></label><button type="submit">Új díj mentése</button></form>
    </section>
  </section>;
}
