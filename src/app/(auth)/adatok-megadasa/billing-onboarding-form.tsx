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
          <input type="checkbox" checked={useProfileName} onChange={(event) => setUseProfileName(event.target.checked)} />
          A számlázási név megegyezik a nevemmel
        </label>

        <label>Számlázási név
          <input name="billingName" value={useProfileName ? profileName : undefined} defaultValue={useProfileName ? undefined : ""} readOnly={useProfileName} required={!useProfileName} onChange={() => undefined} />
          {useProfileName ? <span className="muted form-help">A számlázási név automatikusan: {profileName}</span> : null}
        </label>

        <label>Számlázási irányítószám<input name="billingPostalCode" autoComplete="postal-code" required /></label>
        <label>Számlázási település<input name="billingCity" autoComplete="address-level2" required /></label>
        <label>Számlázási utca<input name="billingStreet" autoComplete="address-line1" required /></label>
        <label>Számlázási házszám<input name="billingHouseNumber" required /></label>
        {customerType === "business" ? <label>Adószám<input name="taxNumber" required /><span className="muted form-help">Vállalkozói számlázás esetén kötelező.</span></label> : <input type="hidden" name="taxNumber" value="" />}
      </fieldset>

      <button type="submit">Adatok mentése és tovább a foglaláshoz</button>
      <p className="muted form-help">A foglalási rendszer az első adatkitöltés befejezéséig nem használható.</p>
    </form>
  );
}
