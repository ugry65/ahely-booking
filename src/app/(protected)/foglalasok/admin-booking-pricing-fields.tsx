"use client";

import { useEffect, useRef, useState } from "react";

type Quote = { rate_source: "booking_override" | "user_override" | "central_tier" | "training_room"; hourly_rate_huf: number; projected_month_normal_minutes: number; amount_huf: number };
type Props = { defaultUserId: string; bookingId?: string | null; existingOverride?: number | null; existingReason?: string | null; allowOverride?: boolean };
const labels: Record<Quote["rate_source"], string> = {
  booking_override: "Foglalásszintű egyedi óradíj",
  user_override: "User egyedi óradíja",
  central_tier: "Központi havi sávos díj",
  training_room: "Tréningterem csoportos alapdíj",
};
function money(value: number) { return new Intl.NumberFormat("hu-HU").format(value) + " Ft"; }

export function AdminBookingPricingFields({ defaultUserId, bookingId, existingOverride = null, existingReason = null, allowOverride = true }: Props) {
  const host = useRef<HTMLFieldSetElement>(null);
  const [custom, setCustom] = useState(existingOverride !== null);
  const [rate, setRate] = useState(existingOverride === null ? "" : String(existingOverride));
  const [reason, setReason] = useState(existingReason ?? "");
  const [revision, setRevision] = useState(0);
  const [quote, setQuote] = useState<Quote | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    const form = host.current?.closest("form");
    if (!form) return;
    const refresh = () => setRevision((value) => value + 1);
    form.addEventListener("change", refresh);
    form.addEventListener("input", refresh);
    return () => { form.removeEventListener("change", refresh); form.removeEventListener("input", refresh); };
  }, []);

  useEffect(() => {
    const form = host.current?.closest("form");
    if (!form) return;
    const controller = new AbortController();
    const timer = window.setTimeout(async () => {
      const data = new FormData(form);
      const payload = {
        userId: String(data.get("targetUserId") || defaultUserId), roomId: String(data.get("roomId") || ""),
        date: String(data.get("date") || ""), startTime: String(data.get("startTime") || ""), endTime: String(data.get("endTime") || ""),
        useType: String(data.get("useType") || "individual"), bookingId: bookingId ?? null,
        hourlyRateOverride: custom ? rate : "",
      };
      if (!payload.userId || !payload.roomId || !payload.date || !payload.startTime || !payload.endTime || (custom && !/^\d+$/.test(rate))) { setQuote(null); return; }
      try {
        const response = await fetch("/api/admin/pricing/quote", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload), signal: controller.signal });
        const result = await response.json() as { quote?: Quote; error?: string };
        if (!response.ok || !result.quote) throw new Error(result.error);
        setQuote(result.quote); setError("");
      } catch { if (!controller.signal.aborted) { setQuote(null); setError("A díjelőnézet jelenleg nem számítható ki."); } }
    }, 180);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [revision, custom, rate, defaultUserId, bookingId]);

  const removingExisting = allowOverride && existingOverride !== null && !custom;
  const rateChanged = custom && rate !== String(existingOverride ?? "");
  return <fieldset ref={host} className="stack"><legend>Óradíj</legend>
    <input type="hidden" name="applyRateOverride" value={allowOverride ? "true" : "false"} />
    {quote ? <div className="message"><strong>{money(quote.hourly_rate_huf)}/óra</strong> · {labels[quote.rate_source]}<br /><span className="muted">A foglalás számított díja: {money(quote.amount_huf)}. Projekció szerinti normál havi idő: {(quote.projected_month_normal_minutes / 60).toLocaleString("hu-HU")} óra.</span></div> : error ? <p className="message error">{error}</p> : <p className="muted">Az automatikus díj a foglalási adatok kitöltése után jelenik meg.</p>}
    {allowOverride ? <label className="inline-check"><input type="checkbox" checked={custom} onChange={(event) => { const checked = event.target.checked; setCustom(checked); setReason(checked ? existingReason ?? "" : ""); setRevision((value) => value + 1); }} /> Egyedi óradíj csak ehhez a foglaláshoz</label> : <p className="muted form-help">Sorozat több alkalmának szerkesztésekor az óradíjak változatlanok maradnak. Foglalásszintű óradíj egyetlen alkalom szerkesztésével módosítható.</p>}
    {allowOverride && custom ? <label>Egyedi óradíj (Ft/óra)<input name="hourlyRateOverride" type="number" min="0" step="1" value={rate} onChange={(event) => { const nextRate = event.target.value; setRate(nextRate); if (existingOverride !== null) setReason(nextRate === String(existingOverride) ? existingReason ?? "" : ""); }} required /></label> : null}
    {allowOverride && (custom || removingExisting) ? <label>{removingExisting ? "Felülírás megszüntetésének indoka" : rateChanged ? "Új módosítás indoka" : "Felülírás indoka"}<input name="rateOverrideReason" maxLength={300} value={reason} onChange={(event) => setReason(event.target.value)} required /></label> : null}
    {allowOverride && custom && existingOverride !== null && !rateChanged ? <p className="muted form-help">Az indok az óradíj változtatása nélkül is javítható; a módosítás külön auditbejegyzést kap.</p> : null}
    {removingExisting ? <p className="muted form-help">Mentéskor a korábbi foglalásszintű felülírás megszűnik, és ismét az automatikus díj érvényesül.</p> : null}
  </fieldset>;
}
