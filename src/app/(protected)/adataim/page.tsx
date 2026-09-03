import { requireActiveProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { ProfileForm } from "./profile-form";

type EditableProfile = {
  first_name: string;
  last_name: string;
  email: string;
  phone: string | null;
  customer_type: "private" | "business";
  billing_name: string | null;
  billing_postal_code: string | null;
  billing_city: string | null;
  billing_street: string | null;
  billing_house_number: string | null;
  tax_number: string | null;
};

function paramValue(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }

export default async function MyDataPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const activeProfile = await requireActiveProfile();
  const params = await searchParams;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("first_name,last_name,email,phone,customer_type,billing_name,billing_postal_code,billing_city,billing_street,billing_house_number,tax_number")
    .eq("id", activeProfile.id)
    .maybeSingle<EditableProfile>();

  return <section className="stack">
    <header className="page-heading profile-page-heading"><div><p className="eyebrow">Saját profil</p><h1>Adataim</h1><p className="muted">Itt tarthatod naprakészen a kapcsolattartási és számlázási adataidat.</p></div></header>
    {paramValue(params.hiba) || paramValue(params.uzenet) ? <p className={`message ${paramValue(params.hiba) ? "error" : "success"}`} role="status">{paramValue(params.hiba) ?? paramValue(params.uzenet)}</p> : null}
    {error || !data ? <p className="message error" role="alert">Az adatok betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : <div className="card wide-card" style={{ maxWidth: "48rem" }}><ProfileForm profile={data} /></div>}
  </section>;
}
