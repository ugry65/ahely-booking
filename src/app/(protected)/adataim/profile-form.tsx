"use client";

import { useState } from "react";
import { updateOwnProfileData } from "./actions";

type ProfileData = {
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

export function ProfileForm({ profile }: { profile: ProfileData }) {
  const profileName = `${profile.last_name} ${profile.first_name}`.trim();
  const [customerType, setCustomerType] = useState<"private" | "business">(profile.customer_type ?? "private");
  const [useProfileName, setUseProfileName] = useState((profile.billing_name ?? "") === profileName);
  const [billingName, setBillingName] = useState(profile.billing_name ?? profileName);

  function toggleProfileName(checked: boolean) {
    setUseProfileName(checked);
    if (checked) setBillingName(profileName);
  }

  return <form action={updateOwnProfileData} className="stack">
    <fieldset>
      <legend>Személyes adatok</legend>
      <label>Vezetéknév<input value={profile.last_name} readOnly aria-readonly="true" /></label>
      <label>Keresztnév<input value={profile.first_name} readOnly aria-readonly="true" /></label>
      <label>E-mail<input value={profile.email} readOnly aria-readonly="true" /></label>
      <p className="muted form-help">A nevet és az e-mail címet csak az A-Hely adminisztrátora módosíthatja.</p>
      <label>Telefonszám<input name="phone" type="tel" autoComplete="tel" required defaultValue={profile.phone ?? ""} /></label>
    </fieldset>

    <fieldset>
      <legend>Számlázási adatok</legend>
      <label>Számla típusa
        <select name="customerType" value={customerType} onChange={(event) => setCustomerType(event.target.value as "private" | "business")}>
          <option value="private">Magánszemély</option>
          <option value="business">Vállalkozó</option>
        </select>
      </label>
      <label className="inline-check">
        <input type="checkbox" checked={useProfileName} onChange={(event) => toggleProfileName(event.target.checked)} />
        A számlázási név megegyezik a nevemmel
      </label>
      <label>Számlázási név<input name="billingName" required value={billingName} readOnly={useProfileName} onChange={(event) => setBillingName(event.target.value)} /></label>
      <fieldset>
        <legend>Számlázási cím</legend>
        <label>Irányítószám<input name="billingPostalCode" autoComplete="postal-code" required defaultValue={profile.billing_postal_code ?? ""} /></label>
        <label>Település<input name="billingCity" autoComplete="address-level2" required defaultValue={profile.billing_city ?? ""} /></label>
        <label>Utca<input name="billingStreet" autoComplete="address-line1" required defaultValue={profile.billing_street ?? ""} /></label>
        <label>Házszám<input name="billingHouseNumber" required defaultValue={profile.billing_house_number ?? ""} /></label>
      </fieldset>
      {customerType === "business" ? <label>Adószám<input name="taxNumber" required defaultValue={profile.tax_number ?? ""} /><span className="muted form-help">Vállalkozói számlázás esetén kötelező.</span></label> : <input type="hidden" name="taxNumber" value="" />}
    </fieldset>

    <button type="submit">Adatok mentése</button>
    <p className="muted form-help">A módosítás naplózott. A foglalási jogosultságokat és más adminisztrációs beállításokat ezen az oldalon nem lehet megváltoztatni.</p>
  </form>;
}
