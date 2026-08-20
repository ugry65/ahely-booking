"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef } from "react";

import { logout } from "@/app/(auth)/actions";

type Props = {
  displayName: string;
  isAdmin: boolean;
};

export function MobileAppNav({ displayName, isAdmin }: Props) {
  const menuRef = useRef<HTMLDetailsElement>(null);
  const pathname = usePathname();

  function closeMenu() {
    if (menuRef.current) menuRef.current.open = false;
  }

  useEffect(() => {
    closeMenu();
  }, [pathname]);

  return (
    <nav className="mobile-app-nav" aria-label="Mobil navigáció">
      <Link href="/foglalasok" className="mobile-app-brand" onClick={closeMenu}><strong>A-Hely</strong></Link>
      <details className="mobile-app-menu" ref={menuRef}>
        <summary aria-label="Menü megnyitása">☰</summary>
        <div className="mobile-app-menu-panel">
          <p className="muted">{displayName}</p>
          <Link href="/foglalasok" onClick={closeMenu}>Foglalási naptár</Link>
          <Link href="/foglalasaim" onClick={closeMenu}>Foglalásaim</Link>
          {isAdmin ? <Link href="/admin/felhasznalok" onClick={closeMenu}>Felhasználók</Link> : null}
          {isAdmin ? <Link href="/admin/hozzaferesek" onClick={closeMenu}>Hozzáférések</Link> : null}
          {isAdmin ? <Link href="/admin/havi-orak" onClick={closeMenu}>Havi órák</Link> : null}
          <form action={logout}><button type="submit">Kijelentkezés</button></form>
        </div>
      </details>
    </nav>
  );
}
