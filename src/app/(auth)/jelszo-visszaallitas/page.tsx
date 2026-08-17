import { updatePassword } from "../actions";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export default async function ResetPasswordPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (!data?.claims?.sub) redirect("/belepes");

  return (
    <div className="auth-shell"><section className="card stack">
      <h1>Új jelszó</h1>
      <p>
        Itt meghívás vagy helyreállítás után állíthatsz be jelszót, illetve
        bejelentkezve a saját jelszavadat módosíthatod.
      </p>
      {params.hiba ? <p className="message" role="alert">{params.hiba}</p> : null}
      <form action={updatePassword} className="stack">
        <label>Új jelszó<input name="password" type="password" minLength={12} autoComplete="new-password" required /></label>
        <button type="submit">Jelszó mentése</button>
      </form>
    </section></div>
  );
}
