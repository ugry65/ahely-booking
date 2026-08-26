import Link from "next/link";

import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { setUserPricingPolicy } from "./actions";

type Profile = {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  is_active: boolean;
};

type PricingPolicy = {
  id: string;
  user_id: string;
  pricing_scheme: "tiered" | "progressive" | "free";
  valid_from: string;
  valid_to: string | null;
  created_at: string;
};

type PriceOverride = {
  id: string;
  user_id: string;
  hourly_rate_huf: number;
  valid_from: string;
  valid_to: string | null;
  reason: string;
  created_at: string;
};

type EffectiveMode = "tiered" | "progressive" | "fixed" | "free";

const LABELS: Record<EffectiveMode, string> = {
  tiered: "Sávos",
  progressive: "Progresszív",
  fixed: "Fix óradíj",
  free: "Free – 0 Ft",
};

function fullName(profile: Profile) {
  return `${profile.last_name} ${profile.first_name}`.trim();
}

function budapestToday() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Budapest",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function monthStart(date: string) {
  return `${date.slice(0, 7)}-01`;
}

function nextMonth(date: string) {
  const [year, month] = date.slice(0, 7).split("-").map(Number);
  return new Date(Date.UTC(year, month, 1)).toISOString().slice(0, 7);
}

function activePolicy(policies: PricingPolicy[], userId: string, onDate: string) {
  return policies
    .filter((policy) => policy.user_id === userId && policy.valid_from <= onDate && (!policy.valid_to || policy.valid_to >= onDate))
    .sort((a, b) => b.valid_from.localeCompare(a.valid_from))[0] ?? null;
}

function activeOverride(overrides: PriceOverride[], userId: string, onDate: string) {
  return overrides
    .filter((item) => item.user_id === userId && item.valid_from <= onDate && (!item.valid_to || item.valid_to >= onDate))
    .sort((a, b) => b.valid_from.localeCompare(a.valid_from))[0] ?? null;
}

function effectiveMode(policies: PricingPolicy[], overrides: PriceOverride[], userId: string, onDate: string) {
  const policy = activePolicy(policies, userId, onDate);
  if (policy?.pricing_scheme === "free") return { mode: "free" as const, rate: null };
  const override = activeOverride(overrides, userId, onDate);
  if (override) return { mode: "fixed" as const, rate: override.hourly_rate_huf };
  return { mode: (policy?.pricing_scheme ?? "tiered") as "tiered" | "progressive", rate: null };
}

function nextEffectiveChange(policies: PricingPolicy[], overrides: PriceOverride[], userId: string, onDate: string) {
  const dates = [
    ...policies.filter((p) => p.user_id === userId && p.valid_from > onDate).map((p) => p.valid_from),
    ...overrides.filter((o) => o.user_id === userId && o.valid_from > onDate).map((o) => o.valid_from),
  ].sort();
  const nextDate = dates[0];
  if (!nextDate) return null;
  return { date: nextDate, ...effectiveMode(policies, overrides, userId, nextDate) };
}

export default async function PricingAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const [profilesResult, policiesResult, overridesResult] = await Promise.all([
    supabase.from("profiles")
      .select("id,first_name,last_name,email,is_active")
      .order("last_name").order("first_name").returns<Profile[]>(),
    supabase.rpc("admin_list_user_pricing_policies"),
    supabase.rpc("admin_list_user_price_overrides"),
  ]);

  const profiles = profilesResult.data ?? [];
  const policies = (policiesResult.data ?? []) as unknown as PricingPolicy[];
  const overrides = (overridesResult.data ?? []) as unknown as PriceOverride[];
  const today = budapestToday();
  const currentMonth = monthStart(today);
  const defaultValidMonth = nextMonth(today);
  const selectedProfile = profiles.find((profile) => profile.id === params.user) ?? null;
  const selectedPolicies = selectedProfile
    ? policies.filter((policy) => policy.user_id === selectedProfile.id).sort((a, b) => b.valid_from.localeCompare(a.valid_from))
    : [];
  const selectedOverrides = selectedProfile
    ? overrides.filter((item) => item.user_id === selectedProfile.id).sort((a, b) => b.valid_from.localeCompare(a.valid_from))
    : [];

  return (
    <section className="stack">
      <header className="page-heading">
        <div>
          <p className="eyebrow">Adminisztráció</p>
          <h1>Díjazás</h1>
          <p className="muted">Userenként állítható havi díjazás. Alapértelmezés: Sávos. Fix óradíj esetén add meg a Ft/óra értéket is.</p>
        </div>
        <Link className="button secondary" href="/admin/felhasznalok">Felhasználók</Link>
      </header>

      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {profilesResult.error || policiesResult.error || overridesResult.error ? <p className="message error" role="alert">A díjazási adatok betöltése nem sikerült.</p> : null}

      <section className="card wide-card stack">
        <h2>Díjazási módok</h2>
        <p className="muted">A mód teljes elszámolási hónaptól érvényes. Precedencia: Free → Fix → Sávos/Progresszív. A Fix óradíj a normál órákra vonatkozik; a nem-Free Tréningterem Csoportos használata külön díjszabás szerint számolódik.</p>
        <div style={{ overflowX: "auto" }}>
          <table className="admin-table">
            <thead><tr><th>Kliens</th><th>Aktuális mód</th><th>Következő változás</th><th>Új mód</th><th>Érvényes ettől</th><th /></tr></thead>
            <tbody>
              {profiles.map((profile) => {
                const current = effectiveMode(policies, overrides, profile.id, today);
                const upcoming = nextEffectiveChange(policies, overrides, profile.id, today);
                return (
                  <tr key={profile.id}>
                    <td><strong>{fullName(profile)}</strong><br /><span className="muted">{profile.email}{profile.is_active ? "" : " · inaktív"}</span></td>
                    <td>{LABELS[current.mode]}{current.mode === "fixed" ? ` · ${current.rate!.toLocaleString("hu-HU")} Ft/óra` : ""}</td>
                    <td>{upcoming ? `${upcoming.date.slice(0, 7)} · ${LABELS[upcoming.mode]}${upcoming.mode === "fixed" ? ` · ${upcoming.rate!.toLocaleString("hu-HU")} Ft/óra` : ""}` : "—"}</td>
                    <td colSpan={3}>
                      <form action={setUserPricingPolicy} className="admin-editor-row compact">
                        <input type="hidden" name="userId" value={profile.id} />
                        <label>Díjazás<select name="pricingScheme" defaultValue={current.mode}><option value="tiered">Sávos</option><option value="progressive">Progresszív</option><option value="fixed">Fix óradíj</option><option value="free">Free – 0 Ft</option></select></label>
                        <label>Fix díj (Ft/óra)<input type="number" name="fixedRate" min="0" step="1" defaultValue={current.mode === "fixed" ? current.rate ?? "" : ""} placeholder="pl. 2200" /></label>
                        <label>Érvényes hónap<input type="month" name="validMonth" min={currentMonth.slice(0, 7)} defaultValue={defaultValidMonth} required /></label>
                        <button type="submit">Mentés</button>
                        <Link className="button secondary" href={`/admin/dijazas?user=${profile.id}`}>Előzmények</Link>
                      </form>
                    </td>
                  </tr>
                );
              })}
              {!profiles.length ? <tr><td colSpan={6} className="muted">Nincs felhasználó.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      {selectedProfile ? <section className="card wide-card stack">
        <div className="page-heading"><div><p className="eyebrow">Díjazási előzmények</p><h2>{fullName(selectedProfile)}</h2><p className="muted">{selectedProfile.email}</p></div><Link className="button secondary" href="/admin/dijazas">Bezárás</Link></div>

        <h3>Pricing policy</h3>
        <div style={{ overflowX: "auto" }}><table className="admin-table"><thead><tr><th>Mód</th><th>Érvényes ettől</th><th>Érvényes eddig</th><th>Rögzítve</th></tr></thead><tbody>
          {selectedPolicies.map((policy) => <tr key={policy.id}><td>{LABELS[policy.pricing_scheme]}</td><td>{policy.valid_from}</td><td>{policy.valid_to ?? "folyamatos"}</td><td>{new Intl.DateTimeFormat("hu-HU", { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Budapest" }).format(new Date(policy.created_at))}</td></tr>)}
          {!selectedPolicies.length ? <tr><td colSpan={4}>Nincs külön policy. A default <strong>Sávos</strong> díjazás érvényes.</td></tr> : null}
        </tbody></table></div>

        <h3>Fix óradíj előzmények</h3>
        <div style={{ overflowX: "auto" }}><table className="admin-table"><thead><tr><th>Óradíj</th><th>Érvényes ettől</th><th>Érvényes eddig</th><th>Indok</th><th>Rögzítve</th></tr></thead><tbody>
          {selectedOverrides.map((item) => <tr key={item.id}><td>{item.hourly_rate_huf.toLocaleString("hu-HU")} Ft/óra</td><td>{item.valid_from}</td><td>{item.valid_to ?? "folyamatos"}</td><td>{item.reason}</td><td>{new Intl.DateTimeFormat("hu-HU", { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Budapest" }).format(new Date(item.created_at))}</td></tr>)}
          {!selectedOverrides.length ? <tr><td colSpan={5}>Nincs Fix óradíj előzmény.</td></tr> : null}
        </tbody></table></div>
      </section> : null}
    </section>
  );
}
