export function parseNonNegativeSafeIntegerHuf(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (!/^\d+$/.test(text)) return null;

  const parsed = Number(text);
  return Number.isSafeInteger(parsed) ? parsed : null;
}
