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

const LABELS: Record<PricingPolicy["pricing_scheme"], string> = {
  tiered: "Sávos",
  progressive: "Progresszív",
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

function nextPolicy(policies: PricingPolicy[], userId: string, onDate: string) {
  return policies
    .filter((policy) => policy.user_id === userId && policy.valid_from > onDate)
    .sort((a, b) => a.valid_from.localeCompare(b.valid_from))[0] ?? null;
}

export default async function PricingAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const [profilesResult, policiesResult] = await Promise.all([
    supabase.from("profiles")
      .select("id,first_name,last_name,email,is_active")
      .order("last_name").order("first_name").returns<Profile[]>(),
    supabase.rpc("admin_list_user_pricing_policies").returns<PricingPolicy[]>(),
  ]);

  const profiles = profilesResult.data ?? [];
  const policies = policiesResult.data ?? [];
  const today = budapestToday();
  const currentMonth = monthStart(today);
  const defaultValidMonth = nextMonth(today);
  const selectedProfile = profiles.find((profile) => profile.id === params.user) ?? null;
  const selectedHistory = selectedProfile
    ? policies.filter((policy) => policy.user_id === selectedProfile.id).sort((a, b) => b.valid_from.localeCompare(a.valid_from))
    : [];

  return (
    <section className="stack">
      <header className="page-heading">
        <div>
          <p className="eyebrow">Adminisztráció</p>
          <h1>Díjazás</h1>
          <p className="muted">Userenként állítható havi díjazási mód. Alapértelmezés: Sávos.</p>
        </div>
        <Link className="button secondary" href="/admin/felhasznalok">Felhasználók</Link>
      </header>

      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {profilesResult.error || policiesResult.error ? <p className="message error" role="alert">A díjazási adatok betöltése nem sikerült.</p> : null}

      <section className="card wide-card stack">
        <h2>Díjazási módok</h2>
        <p className="muted">A mód mindig teljes hónapra érvényes. Múltbeli lezárt hónap nem módosítható. A Free mód minden helyiségre, így a Tréningteremre is 0 Ft.</p>
        <div style={{ overflowX: "auto" }}>
          <table className="admin-table">
            <thead><tr><th>Kliens</th><th>Aktuális mód</th><th>Következő változás</th><th>Új mód</th><th>Érvényes ettől</th><th /></tr></thead>
            <tbody>
              {profiles.map((profile) => {
                const active = activePolicy(policies, profile.id, today);
                const upcoming = nextPolicy(policies, profile.id, today);
                const currentScheme = active?.pricing_scheme ?? "tiered";
                return (
                  <tr key={profile.id}>
                    <td><strong>{fullName(profile)}</strong><br /><span className="muted">{profile.email}{profile.is_active ? "" : " · inaktív"}</span></td>
                    <td>{LABELS[currentScheme]}</td>
                    <td>{upcoming ? `${upcoming.valid_from.slice(0, 7)} · ${LABELS[upcoming.pricing_scheme]}` : "—"}</td>
                    <td colSpan={3}>
                      <form action={setUserPricingPolicy} className="admin-editor-row compact">
                        <input type="hidden" name="userId" value={profile.id} />
                        <label>Díjazás<select name="pricingScheme" defaultValue={currentScheme}><option value="tiered">Sávos</option><option value="progressive">Progresszív</option><option value="free">Free – 0 Ft</option></select></label>
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
        <div style={{ overflowX: "auto" }}><table className="admin-table"><thead><tr><th>Mód</th><th>Érvényes ettől</th><th>Érvényes eddig</th><th>Rögzítve</th></tr></thead><tbody>
          {selectedHistory.map((policy) => <tr key={policy.id}><td>{LABELS[policy.pricing_scheme]}</td><td>{policy.valid_from}</td><td>{policy.valid_to ?? "folyamatos"}</td><td>{new Intl.DateTimeFormat("hu-HU", { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Budapest" }).format(new Date(policy.created_at))}</td></tr>)}
          {!selectedHistory.length ? <tr><td colSpan={4}>Nincs külön beállítás. A default <strong>Sávos</strong> díjazás érvényes.</td></tr> : null}
        </tbody></table></div>
      </section> : null}
    </section>
  );
}
