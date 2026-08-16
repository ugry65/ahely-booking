import { requireActiveProfile } from "@/lib/auth";

export default async function BookingsPage() {
  const profile = await requireActiveProfile();
  return (
    <section>
      <h1>Üdv, {profile.first_name}!</h1>
      <p>A bejelentkezés és a jogosultságellenőrzés működik. A foglalási naptár a következő mérföldkövekben készül.</p>
    </section>
  );
}
