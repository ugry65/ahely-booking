import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { changeInitialPassword } from "../actions";

export default async function InitialPasswordPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!data?.claims?.sub) redirect("/belepes");

  return (
    <div className="auth-shell"><section className="card stack">
      <p className="eyebrow">Első belépés</p>
      <h1>Jelszó megváltoztatása</h1>
      <p>Az adminisztrátor által megadott kezdőjelszót biztonsági okból most kötelező megváltoztatnod.</p>
      {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
      <form action={changeInitialPassword} className="stack">
        <label>Új jelszó<input name="password" type="password" autoComplete="new-password" minLength={12} required /></label>
        <label>Új jelszó még egyszer<input name="confirmation" type="password" autoComplete="new-password" minLength={12} required /></label>
        <button type="submit">Jelszó megváltoztatása</button>
      </form>
    </section></div>
  );
}
