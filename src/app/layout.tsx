import type { Metadata } from "next";

import "./globals.css";
import "./skedda-mobile.css";
import "./mobile-hour-grid.css";
import "./mobile-responsive.css";

export const metadata: Metadata = {
  title: "A-Hely foglalás",
  description: "Az A-Hely saját foglalási és havi elszámolási rendszere",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="hu">
      <body>{children}</body>
    </html>
  );
}
