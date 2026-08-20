import Link from "next/link";

import { logout } from "@/app/(auth)/actions";
import { requireActiveProfile } from "@/lib/auth";

export default async function ProtectedLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const profile = await requireActiveProfile();

  return (
    <main>
      <nav className="desktop-app-nav">
        <Link href="/foglalasok"><strong>A-Hely</strong></Link>
        <Link href="/foglalasaim">Foglalásaim</Link>
        <span>{profile.last_name} {profile.first_name}</span>
        {profile.role === "admin" ? <Link href="/admin/felhasznalok">Felhasználók</Link> : null}
        {profile.role === "admin" ? <Link href="/admin/hozzaferesek">Hozzáférések</Link> : null}
        {profile.role === "admin" ? <Link href="/admin/havi-orak">Havi órák</Link> : null}
        <form action={logout}><button type="submit">Kijelentkezés</button></form>
      </nav>

      <nav className="mobile-app-nav" aria-label="Mobil navigáció">
        <Link href="/foglalasok" className="mobile-app-brand"><strong>A-Hely</strong></Link>
        <details className="mobile-app-menu">
          <summary aria-label="Menü megnyitása">☰</summary>
          <div className="mobile-app-menu-panel">
            <p className="muted">{profile.last_name} {profile.first_name}</p>
            <Link href="/foglalasok">Foglalási naptár</Link>
            <Link href="/foglalasaim">Foglalásaim</Link>
            {profile.role === "admin" ? <Link href="/admin/felhasznalok">Felhasználók</Link> : null}
            {profile.role === "admin" ? <Link href="/admin/hozzaferesek">Hozzáférések</Link> : null}
            {profile.role === "admin" ? <Link href="/admin/havi-orak">Havi órák</Link> : null}
            <form action={logout}><button type="submit">Kijelentkezés</button></form>
          </div>
        </details>
      </nav>
      {children}
    </main>
  );
}
