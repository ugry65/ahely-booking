const MONTH_PATTERN = /^(\d{4})-(0[1-9]|1[0-2])$/;

export type PricingMonthOption = {
  value: string;
  label: string;
};

export function pricingMonthOptions(firstMonth: string, count = 37): PricingMonthOption[] {
  const match = MONTH_PATTERN.exec(firstMonth);
  if (!match || !Number.isInteger(count) || count < 1) return [];

  const firstYear = Number(match[1]);
  const firstMonthIndex = Number(match[2]) - 1;
  const formatter = new Intl.DateTimeFormat("hu-HU", {
    year: "numeric",
    month: "long",
    timeZone: "UTC",
  });

  return Array.from({ length: count }, (_, offset) => {
    const date = new Date(Date.UTC(firstYear, firstMonthIndex + offset, 1));
    return {
      value: date.toISOString().slice(0, 7),
      label: formatter.format(date),
    };
  });
}
