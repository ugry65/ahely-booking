import Link from "next/link";

import { logout } from "@/app/(auth)/actions";
import { requireActiveProfile } from "@/lib/auth";

export default async function ProtectedLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const profile = await requireActiveProfile();

  return (
    <main>
      <nav>
        <Link href="/foglalasok"><strong>A-Hely</strong></Link>
        <Link href="/foglalasaim">Foglalásaim</Link>
        <span>{profile.last_name} {profile.first_name}</span>
        {profile.role === "admin" ? <Link href="/admin/hozzaferesek">Admin</Link> : null}
        <form action={logout}><button type="submit">Kijelentkezés</button></form>
      </nav>
      {children}
    </main>
  );
}
