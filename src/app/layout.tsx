import type { Metadata } from "next";

import "./globals.css";
import "./skedda-mobile.css";
import "./mobile-hour-grid.css";
import "./mobile-responsive.css";
import "./month-picker-responsive.css";
import "./mobile-admin-responsive.css";
import "./form-submit-feedback.css";
import { FormSubmitFeedback } from "./form-submit-feedback";

export const metadata: Metadata = {
  title: "A-Hely foglalás",
  description: "Az A-Hely saját foglalási és havi elszámolási rendszere",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="hu">
      <body>
        <FormSubmitFeedback />
        {children}
      </body>
    </html>
  );
}
