import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { setCentralPricing, setTrainingRoomRate } from "./actions";
import { pricingMonthStart, pricingValidFrom } from "@/lib/admin-pricing-dates";

type Rule = { rule_type: "central_tier" | "training_room"; rule_id: string; min_minutes: number | null; max_minutes: number | null; room_name: string | null; use_type: "individual" | "group" | null; hourly_rate_huf: number; valid_from: string; valid_to: string | null };
function huf(value: number) { return new Intl.NumberFormat("hu-HU").format(value) + " Ft/óra"; }
function period(rule: Rule) { return `${rule.valid_from} – ${rule.valid_to ?? "folyamatos"}`; }
function tierName(rule: Rule) { return rule.max_minutes === 900 ? "1–15 óra" : rule.max_minutes === 3600 ? "15 óra felett–60 óráig" : "60 óra felett"; }
export default async function PricingAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const month = pricingMonthStart();
  const [{ data, error }, monthResult] = await Promise.all([
    supabase.rpc("admin_list_pricing_rules"),
    supabase.rpc("admin_monthly_settlement_close_preview", { p_month: month }),
  ]);
  const monthState = monthResult.data?.[0];
  const monthKnown = !monthResult.error && monthState?.settlement_month === month && typeof monthState.already_closed === "boolean";
  const validFrom = monthKnown ? pricingValidFrom(month, monthState.already_closed) : undefined;
  const cannotSave = Boolean(error) || !monthKnown;
  const rules = (data ?? []) as unknown as Rule[];
  const central = rules.filter((rule) => rule.rule_type === "central_tier");
  const training = rules.filter((rule) => rule.rule_type === "training_room");
  // Backdating must not silently copy an unrelated later scheduled tariff.
  const effectiveAtDefault = (rule: Rule) => validFrom !== undefined
    && rule.valid_from <= validFrom && (rule.valid_to === null || rule.valid_to >= validFrom);
  const initialCentralRate = (minMinutes: number) => central.find((rule) => effectiveAtDefault(rule) && rule.min_minutes === minMinutes)?.hourly_rate_huf;
  const initialTrainingRate = training.find(effectiveAtDefault)?.hourly_rate_huf;
  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Díjszabás</h1><p className="muted">Nyitott aktuális hónapban a hónap első napjától is megadható új díj. A nyitott elszámolás újraszámolódik; a lezárt elszámolások nem változnak. Az egyedi díjak elsőbbsége megmarad.</p></div></header>
    {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
    {error ? <p className="message error" role="alert">A díjszabás betöltése nem sikerült.</p> : null}
    {!monthKnown ? <p className="message error" role="alert">A hónap lezárási állapota nem ellenőrizhető. Díjmódosítás most nem menthető; frissítsd az oldalt.</p> : monthState.already_closed ? <p className="message" role="status">Az aktuális hónap már lezárt. Új díj legkorábban {validFrom} napjától adható meg.</p> : <p className="muted">Legkorábbi kezdődátum: {validFrom}. A visszamenőleges módosítás az adott kezdődátumtól a hónap már megtörtént foglalásainak díját is érintheti.</p>}
    <section className="card wide-card stack"><h2>Központi havi sávos díjak</h2><p className="muted">Nem progresszív számítás: a teljes havi normál óraszám egy sáv óradíját választja.</p>
      <div className="pricing-table-desktop table-scroll"><table className="admin-table"><thead><tr><th>Sáv</th><th>Óradíj</th><th>Érvényesség</th></tr></thead><tbody>{central.map((rule) => <tr key={rule.rule_id}><td>{tierName(rule)}</td><td>{huf(rule.hourly_rate_huf)}</td><td>{period(rule)}</td></tr>)}</tbody></table></div>
      <div className="pricing-list-mobile">{central.map((rule) => <article className="report-mobile-card" key={rule.rule_id}><div className="report-mobile-card-heading"><h3>{tierName(rule)}</h3><span>{huf(rule.hourly_rate_huf)}</span></div><dl className="report-mobile-details"><div><dt>Érvényesség</dt><dd>{period(rule)}</dd></div></dl></article>)}</div>
      <form action={setCentralPricing} className="admin-editor-row"><label>Érvényes ettől<input type="date" name="validFrom" min={validFrom} defaultValue={validFrom} disabled={cannotSave} required /></label><label>1–15 óra<input type="number" name="rate1To15" min="0" step="1" defaultValue={initialCentralRate(60) ?? 2500} required /></label><label>&gt;15–60 óra<input type="number" name="rateOver15To60" min="0" step="1" defaultValue={initialCentralRate(901) ?? 1900} required /></label><label>&gt;60 óra<input type="number" name="rateOver60" min="0" step="1" defaultValue={initialCentralRate(3601) ?? 1700} required /></label><label>Indok<input name="reason" maxLength={300} required placeholder="Miért változik?" /></label><button type="submit" disabled={cannotSave}>Új díjszabás mentése</button></form>
    </section>
    <section className="card wide-card stack"><h2>Tréningterem csoportos alapdíj</h2><p className="muted">Az egyéni Tréningterem-használat normál díjazású. A csoportos alapdíjat a booking- vagy user-szintű egyedi óradíj felülírhatja.</p>
      <div className="pricing-table-desktop table-scroll"><table className="admin-table"><thead><tr><th>Helyiség</th><th>Használat</th><th>Óradíj</th><th>Érvényesség</th></tr></thead><tbody>{training.map((rule) => <tr key={rule.rule_id}><td>{rule.room_name}</td><td>Csoportos</td><td>{huf(rule.hourly_rate_huf)}</td><td>{period(rule)}</td></tr>)}</tbody></table></div>
      <div className="pricing-list-mobile">{training.map((rule) => <article className="report-mobile-card" key={rule.rule_id}><div className="report-mobile-card-heading"><h3>{rule.room_name}</h3><span>{huf(rule.hourly_rate_huf)}</span></div><dl className="report-mobile-details"><div><dt>Használat</dt><dd>Csoportos</dd></div><div><dt>Érvényesség</dt><dd>{period(rule)}</dd></div></dl></article>)}</div>
      <form action={setTrainingRoomRate} className="admin-editor-row compact"><label>Érvényes ettől<input type="date" name="validFrom" min={validFrom} defaultValue={validFrom} disabled={cannotSave} required /></label><label>Óradíj<input type="number" name="hourlyRate" min="0" step="1" defaultValue={initialTrainingRate ?? 5000} required /></label><label>Indok<input name="reason" maxLength={300} required placeholder="Miért változik?" /></label><button type="submit" disabled={cannotSave}>Új díj mentése</button></form>
    </section>
  </section>;
}
