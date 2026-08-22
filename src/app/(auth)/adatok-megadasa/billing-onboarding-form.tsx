"use client";

import { useState } from "react";

import { completeOnboarding } from "./actions";

type Props = {
  firstName: string;
  lastName: string;
  email: string;
};

export function BillingOnboardingForm({ firstName, lastName, email }: Props) {
  const profileName = `${lastName} ${firstName}`.trim();
  const [useProfileName, setUseProfileName] = useState(true);
  const [customerType, setCustomerType] = useState<"private" | "business">("private");
  const [billingName, setBillingName] = useState(profileName);

  function toggleUseProfileName(checked: boolean) {
    setUseProfileName(checked);
    if (checked) setBillingName(profileName);
  }

  return (
    <form action={completeOnboarding} className="stack">
      <input type="hidden" name="firstName" value={firstName} />
      <input type="hidden" name="lastName" value={lastName} />
      <input type="hidden" name="useProfileName" value={useProfileName ? "true" : "false"} />

      <label>Vezetéknév<input value={lastName} readOnly aria-readonly="true" /></label>
      <label>Keresztnév<input value={firstName} readOnly aria-readonly="true" /></label>
      <label>E-mail<input value={email} readOnly aria-readonly="true" /></label>
      <label>Telefonszám<input name="phone" type="tel" autoComplete="tel" required /></label>

      <fieldset className="repeat-options">
        <legend>Számlázás</legend>
        <label>Számla típusa
          <select name="customerType" value={customerType} onChange={(event) => setCustomerType(event.target.value as "private" | "business")}> 
            <option value="private">Magánszemély</option>
            <option value="business">Vállalkozó</option>
          </select>
        </label>

        <label className="inline-check">
          <input type="checkbox" checked={useProfileName} onChange={(event) => toggleUseProfileName(event.target.checked)} />
          A számlázási név megegyezik a nevemmel
        </label>

        <label>Számlázási név
          <input name="billingName" value={billingName} onChange={(event) => setBillingName(event.target.value)} readOnly={useProfileName} required />
          {useProfileName ? <span className="muted form-help">A számlázási név automatikusan: {profileName}</span> : null}
        </label>

        <fieldset className="repeat-options">
          <legend>Számlázási cím</legend>
          <label>Irányítószám<input name="billingPostalCode" autoComplete="postal-code" required /></label>
          <label>Település<input name="billingCity" autoComplete="address-level2" required /></label>
          <label>Utca<input name="billingStreet" autoComplete="address-line1" required /></label>
          <label>Házszám<input name="billingHouseNumber" required /></label>
        </fieldset>

        {customerType === "business" ? <label>Adószám<input name="taxNumber" required /><span className="muted form-help">Vállalkozói számlázás esetén kötelező.</span></label> : <input type="hidden" name="taxNumber" value="" />}
      </fieldset>

      <button type="submit">Adatok mentése és tovább a foglaláshoz</button>
      <p className="muted form-help">A foglalási rendszer az első adatkitöltés befejezéséig nem használható.</p>
    </form>
  );
}
