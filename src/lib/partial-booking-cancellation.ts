export type CancellationRange = { start: string; end: string };

/** Hour-sized choices anchored to the existing booking, including a trailing half hour. */
export function bookingHourParts(start: string, end: string): CancellationRange[] {
  const a = Date.parse(start), b = Date.parse(end);
  if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a || b - a > 86400000) return [];
  const result: CancellationRange[] = [];
  for (let cursor = a; cursor < b; cursor += 3600000) {
    result.push({ start: new Date(cursor).toISOString(), end: new Date(Math.min(cursor + 3600000, b)).toISOString() });
  }
  return result;
}

export function cancellationPreview(start: string, end: string, selected: CancellationRange[], minimumMinutes = 60) {
  const a = Date.parse(start), b = Date.parse(end);
  const sorted = selected.map(r => ({ start: Date.parse(r.start), end: Date.parse(r.end) })).sort((x, y) => x.start - y.start);
  if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a || !sorted.length || sorted.length > 48) return { ok: false as const, error: "Jelöld ki a lemondandó órákat." };
  let cursor = a;
  const remaining: CancellationRange[] = [];
  for (const r of sorted) {
    if (!Number.isFinite(r.start) || !Number.isFinite(r.end) || r.start < cursor || r.end > b || r.end <= r.start) return { ok: false as const, error: "Érvénytelen vagy átfedő időszak." };
    if (r.start > cursor) remaining.push({ start: new Date(cursor).toISOString(), end: new Date(r.start).toISOString() });
    cursor = r.end;
  }
  if (cursor < b) remaining.push({ start: new Date(cursor).toISOString(), end: new Date(b).toISOString() });
  if (remaining.some(r => Date.parse(r.end) - Date.parse(r.start) < minimumMinutes * 60000)) return { ok: false as const, error: `A megmaradó foglalások legalább ${minimumMinutes} percesek legyenek.` };
  return { ok: true as const, remaining };
}
