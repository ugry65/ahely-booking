import { inviteUser } from "./actions";

export default async function UsersAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  return (
    <section className="card stack">
      <h1>Felhasználó meghívása</h1>
      {params.hiba || params.uzenet ? <p className="message" role="status">{params.hiba ?? params.uzenet}</p> : null}
      <form action={inviteUser} className="stack">
        <label>Vezetéknév<input name="lastName" required /></label>
        <label>Keresztnév<input name="firstName" required /></label>
        <label>E-mail<input name="email" type="email" autoComplete="email" required /></label>
        <button type="submit">Meghívó küldése</button>
      </form>
      <p className="muted">A meghívás kizárólag szerveroldalon, service-role kulccsal történik. A kulcs nem kerül a böngészőbe.</p>
    </section>
  );
}
