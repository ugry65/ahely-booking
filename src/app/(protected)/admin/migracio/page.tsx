import { requireAdmin } from "@/lib/auth";

import { MigrationDryRunForm } from "./dry-run-form";

export default async function MigrationAdminPage() {
  await requireAdmin();
  return (
    <section className="stack">
      <header className="page-heading">
        <div>
          <p className="eyebrow">Adminisztráció</p>
          <h1>Migráció</h1>
          <p className="muted">AllBooked forrásadat ellenőrzése és kontrollált production import előkészítése.</p>
        </div>
      </header>
      <MigrationDryRunForm />
    </section>
  );
}
