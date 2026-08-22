import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { importUsersCsv, inviteUser, sendPasswordReset, setUserGroupMembership, setUserRepeatPermission, setUserRole, updateUserProfile } from "./actions";
import { updateGlobalBookingNameVisibility } from "./visibility-actions";

type ManagedProfile = {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  phone: string | null;
  role: "admin" | "user";
  is_active: boolean;
  can_repeat_bookings: boolean;
  customer_type: "private" | "business";
  billing_name: string | null;
  billing_postal_code: string | null;
  billing_city: string | null;
  billing_street: string | null;
  billing_house_number: string | null;
  tax_number: string | null;
  onboarding_completed_at: string | null;
};
type AccessGroup = { id: string; name: string; is_active: boolean };
type GroupMember = { group_id: string; user_id: string };
type AccessOverview = { groups?: AccessGroup[]; group_members?: GroupMember[] };

function BillingFields({ profile }: { profile: ManagedProfile }) {
  return <>
    <label>Telefonszám<input name="phone" type="tel" defaultValue={profile.phone ?? ""} /></label>
    <label>Ügyféltípus<select name="customerType" defaultValue={profile.customer_type ?? "private"}><option value="private">Magánszemély</option><option value="business">Vállalkozó</option></select></label>
    <label>Számlázási név<input name="billingName" defaultValue={profile.billing_name ?? ""} /></label>
    <label>Számlázási irányítószám<input name="billingPostalCode" defaultValue={profile.billing_postal_code ?? ""} /></label>
    <label>Számlázási település<input name="billingCity" defaultValue={profile.billing_city ?? ""} /></label>
    <label>Számlázási utca<input name="billingStreet" defaultValue={profile.billing_street ?? ""} /></label>
    <label>Számlázási házszám<input name="billingHouseNumber" defaultValue={profile.billing_house_number ?? ""} /></label>
    <label>Adószám<input name="taxNumber" defaultValue={profile.tax_number ?? ""} /><span className="muted form-help">Vállalkozó esetén kötelező.</span></label>
  </>;
}

function fullName(profile: ManagedProfile) { return `${profile.last_name} ${profile.first_name}`.trim(); }

export default async function UsersAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const [profilesResult, visibilityResult, accessResult] = await Promise.all([
    supabase.from("profiles")
      .select("id,first_name,last_name,email,phone,role,is_active,can_repeat_bookings,customer_type,billing_name,billing_postal_code,billing_city,billing_street,billing_house_number,tax_number,onboarding_completed_at")
      .order("last_name").order("first_name").returns<ManagedProfile[]>(),
    supabase.from("app_settings").select("value").eq("key", "show_other_booker_names").maybeSingle<{ value: boolean }>(),
    supabase.rpc("admin_room_access_overview"),
  ]);
  const profiles = profilesResult.data ?? [];
  const access = accessResult.error ? {} : accessResult.data as unknown as AccessOverview;
  const groups = (access.groups ?? []).filter((group) => group.is_active).sort((a, b) => a.name.localeCompare(b.name, "hu"));
  const groupMemberships = new Set((access.group_members ?? []).map((member) => `${member.user_id}:${member.group_id}`));
  const showOtherBookerNames = typeof visibilityResult.data?.value === "boolean" ? visibilityResult.data.value : true;
  const query = (params.q ?? "").trim().toLocaleLowerCase("hu-HU");
  const filteredProfiles = query ? profiles.filter((profile) => `${fullName(profile)} ${profile.email} ${profile.phone ?? ""}`.toLocaleLowerCase("hu-HU").includes(query)) : profiles;
  const selectedProfile = profiles.find((profile) => profile.id === params.user) ?? null;
  const groupsForUser = (profileId: string) => groups.filter((group) => groupMemberships.has(`${profileId}:${group.id}`));

  return (
    <section className="stack">
      <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Felhasználók</h1><p className="muted">Áttekinthető felhasználólista, helyiségcsoportok, szerepkörök és törzsadatok.</p></div><Link className="button secondary" href="/admin/helyisegek">Helyiségek</Link></header>
      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {profilesResult.error || accessResult.error ? <p className="message error" role="alert">A felhasználói adminisztrációs adatok betöltése nem sikerült.</p> : null}

      <section className="card wide-card stack">
        <div className="page-heading"><div><h2>Felhasználói lista</h2><p className="muted">A helyiségcsoportokból kapott foglalási jogok mellett az egyedi user–szoba kivételek továbbra is megmaradnak.</p></div>
          <form method="get" className="admin-editor-row compact"><label>Keresés<input name="q" defaultValue={params.q ?? ""} placeholder="Név, e-mail vagy telefon" /></label><button type="submit">Keresés</button>{query ? <Link className="button secondary" href="/admin/felhasznalok">Törlés</Link> : null}</form>
        </div>
        <div style={{ overflowX: "auto" }}><table className="admin-table"><thead><tr><th>Név</th><th>E-mail</th><th>Telefonszám</th><th>Helyiségcsoport</th><th>Ismétlés</th><th>Szerepkör</th><th>Állapot</th><th /></tr></thead><tbody>
          {filteredProfiles.map((profile) => {
            const profileGroups = groupsForUser(profile.id);
            return <tr key={profile.id}><td><strong>{fullName(profile)}</strong></td><td>{profile.email}</td><td>{profile.phone || "—"}</td><td>{profileGroups.length ? profileGroups.map((group) => group.name).join(", ") : "—"}</td><td>{profile.role === "admin" ? "Admin" : profile.can_repeat_bookings ? "Igen" : "Nem"}</td><td>{profile.role === "admin" ? "Adminisztrátor" : "Normál felhasználó"}</td><td>{profile.is_active ? "Aktív" : "Inaktív"}</td><td><Link className="button secondary" href={`/admin/felhasznalok?${new URLSearchParams({ ...(params.q ? { q: params.q } : {}), user: profile.id }).toString()}`}>Szerkesztés</Link></td></tr>;
          })}
          {!filteredProfiles.length ? <tr><td colSpan={8} className="muted">Nincs a keresésnek megfelelő felhasználó.</td></tr> : null}
        </tbody></table></div>
      </section>

      {selectedProfile ? <section className="card wide-card stack">
        <div className="page-heading"><div><p className="eyebrow">Felhasználó szerkesztése</p><h2>{fullName(selectedProfile)}</h2><p className="muted">{selectedProfile.email}</p></div><Link className="button secondary" href={`/admin/felhasznalok${params.q ? `?${new URLSearchParams({ q: params.q }).toString()}` : ""}`}>Bezárás</Link></div>

        <div className="admin-grid">
          <section className="stack"><h3>Szerepkör</h3><form action={setUserRole} className="admin-editor-row compact"><input type="hidden" name="userId" value={selectedProfile.id} /><label>Jogosultsági szint<select name="role" defaultValue={selectedProfile.role}><option value="user">Normál felhasználó</option><option value="admin">Adminisztrátor</option></select></label><button type="submit">Szerepkör mentése</button></form><p className="muted form-help">Az utolsó aktív adminisztrátort a backend nem engedi lefokozni.</p></section>
          <section className="stack"><h3>Ismétlődő foglalás</h3><form action={setUserRepeatPermission} className="admin-editor-row compact"><input type="hidden" name="userId" value={selectedProfile.id} /><input type="hidden" name="canRepeatBookings" value="false" /><label className="inline-check"><input type="checkbox" name="canRepeatBookings" value="true" defaultChecked={selectedProfile.can_repeat_bookings} /> Ismétlődő foglalás engedélyezve</label><button type="submit">Mentés</button></form><p className="muted form-help">User-szintű jogosultság: bekapcsolva minden olyan normál helyiségben ismételhet, amelyet foglalhat. Tréningteremben normál user továbbra sem ismételhet; adminra ez a korlátozás nem vonatkozik.</p></section>
          <section className="stack"><h3>Helyiségcsoportok</h3>{groups.map((group) => <form action={setUserGroupMembership} className="admin-editor-row compact" key={group.id}><input type="hidden" name="userId" value={selectedProfile.id} /><input type="hidden" name="groupId" value={group.id} /><input type="hidden" name="isMember" value="false" /><label className="inline-check"><input type="checkbox" name="isMember" value="true" defaultChecked={groupMemberships.has(`${selectedProfile.id}:${group.id}`)} /> {group.name}</label><button type="submit">Mentés</button></form>)}<p className="muted form-help">A csoport foglalási jogot ad; az ismétlődési jog külön, user-szinten kezelendő.</p><Link href="/admin/hozzaferesek" className="button secondary">Egyedi helyiségjogok</Link></section>
        </div>

        <section className="stack"><h3>Törzs- és számlázási adatok</h3><form action={updateUserProfile} className="admin-editor-row"><input type="hidden" name="userId" value={selectedProfile.id} /><input type="hidden" name="isActive" value="false" /><label>Vezetéknév<input name="lastName" defaultValue={selectedProfile.last_name} required /></label><label>Keresztnév<input name="firstName" defaultValue={selectedProfile.first_name} required /></label><label>E-mail<input value={selectedProfile.email} readOnly aria-readonly="true" /></label><BillingFields profile={selectedProfile} /><label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked={selectedProfile.is_active} /> Aktív</label><button type="submit">Adatok mentése</button></form>
          <form action={sendPasswordReset}><input type="hidden" name="userId" value={selectedProfile.id} /><button type="submit" className="button secondary" disabled={!selectedProfile.is_active}>{selectedProfile.onboarding_completed_at ? "Jelszó-visszaállító link küldése" : "Aktiváló / jelszóbeállító link küldése"}</button></form>
        </section>
      </section> : null}

      <section className="card wide-card stack"><h2>Naptári névláthatóság</h2><p className="muted">Kikapcsolva a normál user másoknál csak a „Foglalt” jelzést látja; az admin mindig látja a nevet.</p><form action={updateGlobalBookingNameVisibility} className="admin-editor-row compact"><input type="hidden" name="visible" value="false" /><label className="inline-check"><input type="checkbox" name="visible" value="true" defaultChecked={showOtherBookerNames} /> Más foglalók neve látható</label><button type="submit">Mentés</button></form></section>

      <div className="admin-grid"><section className="card stack"><h2>Új felhasználó</h2><form action={inviteUser} className="stack"><label>Vezetéknév<input name="lastName" required /></label><label>Keresztnév<input name="firstName" required /></label><label>E-mail<input name="email" type="email" autoComplete="email" required /></label><button type="submit">Felhasználó létrehozása</button></form><p className="muted">Létrehozáskor nem küldünk automatikusan levelet.</p></section>
        <section className="card stack"><h2>Felhasználók importja</h2><p className="muted">CSV: név + e-mail. Az import nem küld automatikus aktiváló levelet.</p><form action={importUsersCsv} className="stack"><label>CSV fájl<input name="file" type="file" accept=".csv,text/csv" required /></label><button type="submit">CSV importálása</button></form><p className="muted form-help">Kötelező oszlopok: <code>last_name, first_name, email</code>.</p></section></div>
    </section>
  );
}
