import type { Metadata, Viewport } from "next";

import "./globals.css";
import "./skedda-mobile.css";
import "./mobile-hour-grid.css";
import { PwaRegister } from "./pwa-register";

export const metadata: Metadata = {
  title: "A-Hely foglalás",
  description: "Az A-Hely saját foglalási és havi elszámolási rendszere",
  applicationName: "A-Hely foglalás",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    title: "A-Hely",
    statusBarStyle: "default",
  },
  icons: {
    apple: "/pwa-icon-192.png",
  },
};

export const viewport: Viewport = {
  themeColor: "#235c43",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="hu">
      <body>
        <PwaRegister />
        {children}
      </body>
    </html>
  );
}
