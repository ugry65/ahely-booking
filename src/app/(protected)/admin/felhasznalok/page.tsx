import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { inviteUser, updateBookingNameVisibility } from "./actions";

type ManagedProfile = {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  is_active: boolean;
  other_booker_names_visible: boolean;
};

export default async function UsersAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id,first_name,last_name,email,is_active,other_booker_names_visible")
    .order("last_name")
    .order("first_name")
    .returns<ManagedProfile[]>();

  return (
    <section className="stack">
      <h1>Felhasználók</h1>
      {params.hiba || params.uzenet ? <p className="message" role="status">{params.hiba ?? params.uzenet}</p> : null}
      <div className="admin-grid">
        <div className="card stack">
          <h2>Felhasználó meghívása</h2>
          <form action={inviteUser} className="stack">
            <label>Vezetéknév<input name="lastName" required /></label>
            <label>Keresztnév<input name="firstName" required /></label>
            <label>E-mail<input name="email" type="email" autoComplete="email" required /></label>
            <button type="submit">Meghívó küldése</button>
          </form>
          <p className="muted">A meghívás kizárólag szerveroldalon, service-role kulccsal történik.</p>
        </div>

        <div className="card wide-card stack">
          <h2>Névláthatóság</h2>
          <p className="muted">Ha kikapcsolod, a felhasználó mások foglalásánál csak a foglaltságot látja. A saját foglalását továbbra is felismeri.</p>
          <div className="user-settings-list">
            {(profiles ?? []).map((profile) => (
              <form action={updateBookingNameVisibility} className="user-setting-row" key={profile.id}>
                <input type="hidden" name="userId" value={profile.id} />
                <div>
                  <strong>{profile.last_name} {profile.first_name}</strong>
                  <div className="muted">{profile.email}{profile.is_active ? "" : " · Inaktív"}</div>
                </div>
                <label className="inline-check">
                  <input type="hidden" name="visible" value="false" />
                  <input type="checkbox" name="visible" value="true" defaultChecked={profile.other_booker_names_visible} />
                  Más foglalók neve látható
                </label>
                <button type="submit">Mentés</button>
              </form>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
