/** Pricing uses Budapest calendar months, independently of the server timezone. */
export function pricingMonthStart(asOf = new Date()): string {
  const parts = new Intl.DateTimeFormat("en", {
    timeZone: "Europe/Budapest", year: "numeric", month: "2-digit",
  }).formatToParts(asOf);
  const year = parts.find((part) => part.type === "year")!.value;
  const month = parts.find((part) => part.type === "month")!.value;
  return `${year}-${month}-01`;
}

export function pricingValidFrom(monthStart: string, alreadyClosed: boolean): string {
  if (!alreadyClosed) return monthStart;
  const [year, month] = monthStart.split("-").map(Number);
  return new Date(Date.UTC(year, month, 1)).toISOString().slice(0, 10);
}
