import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { importUsersCsv, inviteUser, sendPasswordReset, updateUserProfile } from "./actions";

type ManagedProfile = {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  phone: string | null;
  is_active: boolean;
  customer_type: "private" | "business";
  billing_postal_code: string | null;
  billing_city: string | null;
  billing_street: string | null;
  billing_house_number: string | null;
  tax_number: string | null;
};

function BillingFields({ profile }: { profile?: ManagedProfile }) {
  return <>
    <label>Telefonszám<input name="phone" type="tel" defaultValue={profile?.phone ?? ""} /></label>
    <label>Ügyféltípus
      <select name="customerType" defaultValue={profile?.customer_type ?? "private"}>
        <option value="private">Magánszemély</option>
        <option value="business">Vállalkozó</option>
      </select>
    </label>
    <label>Számlázási irányítószám<input name="billingPostalCode" defaultValue={profile?.billing_postal_code ?? ""} /></label>
    <label>Számlázási település<input name="billingCity" defaultValue={profile?.billing_city ?? ""} /></label>
    <label>Számlázási utca<input name="billingStreet" defaultValue={profile?.billing_street ?? ""} /></label>
    <label>Számlázási házszám<input name="billingHouseNumber" defaultValue={profile?.billing_house_number ?? ""} /></label>
    <label>Adószám<input name="taxNumber" defaultValue={profile?.tax_number ?? ""} /><span className="muted form-help">Vállalkozó esetén kötelező.</span></label>
  </>;
}

export default async function UsersAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const { data: profiles, error } = await supabase
    .from("profiles")
    .select("id,first_name,last_name,email,phone,is_active,customer_type,billing_postal_code,billing_city,billing_street,billing_house_number,tax_number")
    .order("last_name")
    .order("first_name")
    .returns<ManagedProfile[]>();

  return (
    <section className="stack">
      <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Felhasználók</h1><p className="muted">Törzsadatok, számlázási adatok, import és jelszó-visszaállítás.</p></div></header>
      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {error ? <p className="message error" role="alert">A felhasználók betöltése nem sikerült.</p> : null}

      <div className="admin-grid">
        <section className="card stack">
          <h2>Új felhasználó meghívása</h2>
          <form action={inviteUser} className="stack">
            <input type="hidden" name="isActive" value="true" />
            <label>Vezetéknév<input name="lastName" required /></label>
            <label>Keresztnév<input name="firstName" required /></label>
            <label>E-mail<input name="email" type="email" autoComplete="email" required /></label>
            <BillingFields />
            <button type="submit">Felhasználó létrehozása és meghívó küldése</button>
          </form>
          <p className="muted">A meghívás szerveroldalon történik. Jelszó nem jelenik meg és nem kerül az alkalmazás adatbázisába.</p>
        </section>

        <section className="card stack">
          <h2>Meglévő felhasználók importja</h2>
          <p className="muted">CSV feltöltés. Az import nem küld automatikusan meghívót vagy jelszó-visszaállító levelet.</p>
          <form action={importUsersCsv} className="stack">
            <label>CSV fájl<input name="file" type="file" accept=".csv,text/csv" required /></label>
            <button type="submit">CSV importálása</button>
          </form>
          <p className="muted form-help">Kötelező oszlopok: <code>last_name, first_name, email</code>. Opcionális: <code>phone, customer_type, billing_postal_code, billing_city, billing_street, billing_house_number, tax_number, is_active</code>.</p>
        </section>
      </div>

      <section className="card wide-card stack">
        <h2>Felhasználói törzsadatok</h2>
        <p className="muted">A számlázási cím opcionális. Vállalkozó esetén az adószám kötelező. Az e-mail cím ebben a fázisban az Auth-azonosító miatt csak olvasható.</p>
        <div className="admin-permission-list">
          {(profiles ?? []).map((profile) => (
            <details key={profile.id}>
              <summary>{profile.last_name} {profile.first_name} · {profile.email}{profile.is_active ? "" : " · Inaktív"}</summary>
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
                  <button type="submit" className="button secondary" disabled={!profile.is_active}>Jelszó-visszaállító link küldése</button>
                </form>
              </div>
            </details>
          ))}
        </div>
      </section>
    </section>
  );
}
