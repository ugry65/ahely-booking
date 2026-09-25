import { requireAdmin } from "@/lib/auth";

import { MigrationDryRunForm } from "./dry-run-form";

export default async function MigrationAdminPage() {
  await requireAdmin();
  return (
    <section className="stack migration-page">
      <header className="page-heading">
        <div>
          <p className="eyebrow">Adminisztráció</p>
          <h1>Migráció</h1>
          <p className="muted">AllBooked/Skedda ügyfelek és foglalásaik egyenkénti, kontrollált átmigrálása.</p>
        </div>
      </header>
      <MigrationDryRunForm />
    </section>
  );
}
