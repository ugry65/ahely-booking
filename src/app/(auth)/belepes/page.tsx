import Link from "next/link";

import { login } from "../actions";

export default async function LoginPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const message = params.hiba === "inaktiv" ? "A hozzáférésed jelenleg inaktív." : params.hiba ?? params.uzenet;

  return (
    <div className="auth-shell">
      <section className="card stack">
        <div><p className="muted">A-Hely</p><h1>Bejelentkezés</h1></div>
        {message ? <p className="message" role="status">{message}</p> : null}
        <form action={login} className="stack">
          <label>E-mail<input name="email" type="email" autoComplete="email" required /></label>
          <label>Jelszó<input name="password" type="password" autoComplete="current-password" required /></label>
          <button type="submit">Belépés</button>
        </form>
        <Link href="/elfelejtett-jelszo">Elfelejtetted a jelszavad?</Link>
        <p className="muted">Nyilvános regisztráció nincs; új hozzáférést az adminisztrátor ad.</p>
      </section>
    </div>
  );
}
