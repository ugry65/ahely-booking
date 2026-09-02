"use client";

import type { FormEvent } from "react";

import { closeMonthlySettlement } from "./actions";

export function SettlementCloseForm({
  userId,
  userName,
  month,
  returnMonths,
}: {
  userId: string;
  userName: string;
  month: string;
  returnMonths: string;
}) {
  function confirmClose(event: FormEvent<HTMLFormElement>) {
    const accepted = window.confirm(
      `${userName} ${month} havi elszámolását véglegesen lezárod?\n\nA lezárt pénzügyi snapshot később nem módosítható közvetlenül.`,
    );
    if (!accepted) event.preventDefault();
  }

  return (
    <form action={closeMonthlySettlement} onSubmit={confirmClose}>
      <input type="hidden" name="userId" value={userId} />
      <input type="hidden" name="month" value={month} />
      <input type="hidden" name="returnMonths" value={returnMonths} />
      <button type="submit">Hónap lezárása</button>
    </form>
  );
}
