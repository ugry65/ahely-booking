import Link from "next/link";

import { requestPasswordReset } from "../actions";

export default async function ForgotPasswordPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  return (
    <div className="auth-shell"><section className="card stack">
      <h1>Jelszó-visszaállítás</h1>
      {params.uzenet ? <p className="message" role="status">{params.uzenet}</p> : null}
      <form action={requestPasswordReset} className="stack">
        <label>E-mail<input name="email" type="email" autoComplete="email" required /></label>
        <button type="submit">Visszaállító levél kérése</button>
      </form>
      <Link href="/belepes">Vissza a belépéshez</Link>
    </section></div>
  );
}
