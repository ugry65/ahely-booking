import type { BookingEmailEventType, BookingEmailPayloadV1, BookingEmailState } from "./schema";

export type RenderedBookingEmail = {
  subject: string;
  text: string;
  html: string;
};

const dateTime = new Intl.DateTimeFormat("hu-HU", {
  timeZone: "Europe/Budapest",
  year: "numeric",
  month: "long",
  day: "numeric",
  weekday: "long",
  hour: "2-digit",
  minute: "2-digit",
});

function when(startAt: string, endAt: string): string {
  return `${dateTime.format(new Date(startAt))} – ${dateTime.format(new Date(endAt))}`;
}

function useTypeLabel(value: BookingEmailState["useType"]): string {
  return value === "group" ? "Csoportos" : "Egyéni";
}

function scopeLabel(payload: BookingEmailPayloadV1): string {
  if (payload.scope === "single") return "Egyedi foglalás";
  if (payload.scope === "occurrence") return "A sorozat egy alkalma";
  if (payload.scope === "following") return "A kiválasztott és az azt követő alkalmak";
  return "Teljes sorozat";
}

function eventLabel(eventType: BookingEmailEventType, summary: boolean): string {
  if (eventType === "booking.created") return summary ? "Ismétlődő foglalás visszaigazolása" : "Foglalás visszaigazolása";
  if (eventType === "booking.updated") return summary ? "Foglalássorozat módosítva" : "Foglalás módosítva";
  return summary ? "Foglalássorozat lemondva" : "Foglalás lemondva";
}

function cleanHeader(value: string): string {
  return value.replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim();
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function stateLines(label: string, value: BookingEmailState): string[] {
  return [
    label,
    `Helyiség: ${value.roomName}`,
    `Időpont: ${when(value.startAt, value.endAt)}`,
    `Használat: ${useTypeLabel(value.useType)}`,
    ...(value.bookingTitle ? [`Foglalás címe: ${value.bookingTitle}`] : []),
  ];
}

function row(label: string, value: string): string {
  return `<tr><th style="padding:6px 12px 6px 0;text-align:left;vertical-align:top;color:#526057">${escapeHtml(label)}</th><td style="padding:6px 0;color:#18231d">${escapeHtml(value)}</td></tr>`;
}

export function renderBookingEmail(
  eventType: BookingEmailEventType,
  payload: BookingEmailPayloadV1,
): RenderedBookingEmail {
  const summary = payload.scope === "following" || payload.scope === "series";
  const heading = eventLabel(eventType, summary);
  const subject = cleanHeader(`${heading} – ${payload.roomName}`);
  const adminNotice = payload.performedByAdmin
    ? "A műveletet az A-Hely adminisztrátora végezte a nevedben."
    : undefined;

  const details = [
    `Hatókör: ${scopeLabel(payload)}`,
    `Helyiség: ${payload.roomName}`,
    `Időpont: ${when(payload.startAt, payload.endAt)}`,
    `Használat: ${useTypeLabel(payload.useType)}`,
    ...(payload.bookingTitle ? [`Foglalás címe: ${payload.bookingTitle}`] : []),
    ...(summary ? [
      `Érintett alkalmak: ${payload.affectedCount}`,
      `Első–utolsó érintett időpont: ${when(payload.firstStartAt, payload.lastEndAt)}`,
    ] : []),
    ...(payload.cancellationReason ? [`Lemondás oka: ${payload.cancellationReason}`] : []),
  ];

  const updateLines = eventType === "booking.updated" && payload.before && payload.after
    ? [...stateLines("Korábbi adatok:", payload.before), "", ...stateLines("Új adatok:", payload.after)]
    : [];
  const text = [
    `Kedves ${payload.recipientName}!`, "", heading, "", ...details,
    ...(updateLines.length ? ["", ...updateLines] : []),
    ...(adminNotice ? ["", adminNotice] : []),
    "", "Üdvözlettel:", "A-Hely",
  ].join("\n");

  const updateHtml = eventType === "booking.updated" && payload.before && payload.after
    ? `<h2 style="font-size:18px;color:#1f6248">Korábbi adatok</h2><table role="presentation">${row("Helyiség", payload.before.roomName)}${row("Időpont", when(payload.before.startAt, payload.before.endAt))}${row("Használat", useTypeLabel(payload.before.useType))}${payload.before.bookingTitle ? row("Foglalás címe", payload.before.bookingTitle) : ""}</table><h2 style="font-size:18px;color:#1f6248">Új adatok</h2><table role="presentation">${row("Helyiség", payload.after.roomName)}${row("Időpont", when(payload.after.startAt, payload.after.endAt))}${row("Használat", useTypeLabel(payload.after.useType))}${payload.after.bookingTitle ? row("Foglalás címe", payload.after.bookingTitle) : ""}</table>`
    : "";
  const summaryRows = summary
    ? `${row("Érintett alkalmak", String(payload.affectedCount))}${row("Első–utolsó időpont", when(payload.firstStartAt, payload.lastEndAt))}`
    : "";

  const html = `<!doctype html><html lang="hu"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escapeHtml(subject)}</title></head><body style="margin:0;background:#f4f2eb;font-family:Arial,sans-serif;color:#18231d"><div style="display:none;max-height:0;overflow:hidden">${escapeHtml(heading)}</div><main style="max-width:620px;margin:0 auto;padding:28px 18px"><div style="background:#fff;border:1px solid #d8d4c8;border-radius:14px;padding:28px"><p>Kedves ${escapeHtml(payload.recipientName)}!</p><h1 style="font-size:24px;color:#1f6248">${escapeHtml(heading)}</h1><table role="presentation">${row("Hatókör", scopeLabel(payload))}${row("Helyiség", payload.roomName)}${row("Időpont", when(payload.startAt, payload.endAt))}${row("Használat", useTypeLabel(payload.useType))}${payload.bookingTitle ? row("Foglalás címe", payload.bookingTitle) : ""}${summaryRows}${payload.cancellationReason ? row("Lemondás oka", payload.cancellationReason) : ""}</table>${updateHtml}${adminNotice ? `<p style="margin-top:22px;padding:12px;background:#eef5f1;border-radius:8px">${escapeHtml(adminNotice)}</p>` : ""}<p style="margin-top:26px">Üdvözlettel:<br><strong>A-Hely</strong></p></div></main></body></html>`;

  return { subject, text, html };
}
