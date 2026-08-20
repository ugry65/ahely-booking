import Link from "next/link";

import { logout } from "@/app/(auth)/actions";
import { requireActiveProfile } from "@/lib/auth";
import { MobileAppNav } from "./mobile-app-nav";

export default async function ProtectedLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const profile = await requireActiveProfile();
  const displayName = `${profile.last_name} ${profile.first_name}`.trim();

  return (
    <main>
      <nav className="desktop-app-nav">
        <Link href="/foglalasok"><strong>A-Hely</strong></Link>
        <Link href="/foglalasaim">Foglalásaim</Link>
        <span>{displayName}</span>
        {profile.role === "admin" ? <Link href="/admin/felhasznalok">Felhasználók</Link> : null}
        {profile.role === "admin" ? <Link href="/admin/hozzaferesek">Hozzáférések</Link> : null}
        {profile.role === "admin" ? <Link href="/admin/havi-orak">Havi órák</Link> : null}
        <form action={logout}><button type="submit">Kijelentkezés</button></form>
      </nav>

      <MobileAppNav displayName={displayName} isAdmin={profile.role === "admin"} />
      {children}
    </main>
  );
}
