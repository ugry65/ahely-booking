import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { importUsersCsv, inviteUser, sendPasswordReset, updateUserProfile } from "./actions";
import { updateGlobalBookingNameVisibility } from "./visibility-actions";

type ManagedProfile = {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  phone: string | null;
  is_active: boolean;
  customer_type: "private" | "business";
  billing_name: string | null;
  billing_postal_code: string | null;
  billing_city: string | null;
  billing_street: string | null;
  billing_house_number: string | null;
  tax_number: string | null;
  onboarding_completed_at: string | null;
};

function BillingFields({ profile }: { profile: ManagedProfile }) {
  return <>
    <label>Telefonszám<input name="phone" type="tel" defaultValue={profile.phone ?? ""} /></label>
    <label>Ügyféltípus
      <select name="customerType" defaultValue={profile.customer_type ?? "private"}>
        <option value="private">Magánszemély</option>
        <option value="business">Vállalkozó</option>
      </select>
    </label>
    <label>Számlázási név<input name="billingName" defaultValue={profile.billing_name ?? ""} /></label>
    <label>Számlázási irányítószám<input name="billingPostalCode" defaultValue={profile.billing_postal_code ?? ""} /></label>
    <label>Számlázási település<input name="billingCity" defaultValue={profile.billing_city ?? ""} /></label>
    <label>Számlázási utca<input name="billingStreet" defaultValue={profile.billing_street ?? ""} /></label>
    <label>Számlázási házszám<input name="billingHouseNumber" defaultValue={profile.billing_house_number ?? ""} /></label>
    <label>Adószám<input name="taxNumber" defaultValue={profile.tax_number ?? ""} /><span className="muted form-help">Vállalkozó esetén kötelező.</span></label>
  </>;
}

export default async function UsersAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const [profilesResult, visibilityResult] = await Promise.all([
    supabase.from("profiles")
      .select("id,first_name,last_name,email,phone,is_active,customer_type,billing_name,billing_postal_code,billing_city,billing_street,billing_house_number,tax_number,onboarding_completed_at")
      .order("last_name").order("first_name").returns<ManagedProfile[]>(),
    supabase.from("app_settings").select("value").eq("key", "show_other_booker_names").maybeSingle<{ value: boolean }>(),
  ]);
  const profiles = profilesResult.data;
  const showOtherBookerNames = typeof visibilityResult.data?.value === "boolean" ? visibilityResult.data.value : true;

  return (
    <section className="stack">
      <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Felhasználók</h1><p className="muted">Felhasználók létrehozása, aktiválása, törzsadatai és számlázási adatai.</p></div></header>
      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {profilesResult.error ? <p className="message error" role="alert">A felhasználók betöltése nem sikerült.</p> : null}

      <section className="card wide-card stack">
        <h2>Naptári névláthatóság</h2>
        <p className="muted">Ez globális beállítás. Alapból mindenki látja, ki foglalta az időpontot. Kikapcsolva a normál user másoknál csak a „Foglalt” jelzést látja; a saját foglalását továbbra is felismeri, az admin pedig mindig látja a nevet.</p>
        <form action={updateGlobalBookingNameVisibility} className="admin-editor-row compact">
          <input type="hidden" name="visible" value="false" />
          <label className="inline-check"><input type="checkbox" name="visible" value="true" defaultChecked={showOtherBookerNames} /> Más foglalók neve látható</label>
          <button type="submit">Mentés</button>
        </form>
      </section>

      <div className="admin-grid">
        <section className="card stack">
          <h2>Új felhasználó létrehozása</h2>
          <form action={inviteUser} className="stack">
            <label>Vezetéknév<input name="lastName" required /></label>
            <label>Keresztnév<input name="firstName" required /></label>
            <label>E-mail<input name="email" type="email" autoComplete="email" required /></label>
            <button type="submit">Felhasználó létrehozása</button>
          </form>
          <p className="muted">A létrehozáskor nem küldünk levelet. Ezután a user sorában külön indíthatod az aktiváló/jelszóbeállító linket. A számlázási adatokat a felhasználó az első belépéskor tölti ki.</p>
        </section>

        <section className="card stack">
          <h2>Meglévő felhasználók importja</h2>
          <p className="muted">CSV feltöltés kizárólag név + e-mail adatokkal. Az import nem küld automatikusan aktiváló levelet.</p>
          <form action={importUsersCsv} className="stack">
            <label>CSV fájl<input name="file" type="file" accept=".csv,text/csv" required /></label>
            <button type="submit">CSV importálása</button>
          </form>
          <p className="muted form-help">Kötelező oszlopok: <code>last_name, first_name, email</code>.</p>
        </section>
      </div>

      <section className="card wide-card stack">
        <h2>Felhasználói törzsadatok</h2>
        <p className="muted">Az első aktiváláskor a user maga adja meg a telefonszámát, számlázási nevét és címét. Vállalkozói számlázásnál az adószám kötelező. Az admin később szükség esetén korrigálhatja az adatokat.</p>
        <div className="admin-permission-list">
          {(profiles ?? []).map((profile) => (
            <details key={profile.id}>
              <summary>{profile.last_name} {profile.first_name} · {profile.email}{profile.is_active ? "" : " · Inaktív"}{profile.onboarding_completed_at ? " · Aktivált" : " · Aktiválásra vár"}</summary>
              <div className="stack" style={{ paddingTop: ".8rem" }}>
                <form action={updateUserProfile} className="admin-editor-row">
                  <input type="hidden" name="userId" value={profile.id} />
                  <input type="hidden" name="isActive" value="false" />
                  <label>Vezetéknév<input name="lastName" defaultValue={profile.last_name} required /></label>
                  <label>Keresztnév<input name="firstName" defaultValue={profile.first_name} required /></label>
                  <label>E-mail<input value={profile.email} readOnly aria-readonly="true" /></label>
                  <BillingFields profile={profile} />
                  <label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked={profile.is_active} /> Aktív</label>
                  <button type="submit">Mentés</button>
                </form>
                <form action={sendPasswordReset}>
                  <input type="hidden" name="userId" value={profile.id} />
                  <button type="submit" className="button secondary" disabled={!profile.is_active}>{profile.onboarding_completed_at ? "Jelszó-visszaállító link küldése" : "Aktiváló / jelszóbeállító link küldése"}</button>
                </form>
              </div>
            </details>
          ))}
        </div>
      </section>
    </section>
  );
}
