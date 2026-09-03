import { describe, expect, it, vi } from "vitest";
import {
  buildOutboundBookingEmail,
  classifyEmailTransportError,
  createBookingEmailSender,
  createCaptureTransport,
  createNodemailerCompatibleTransport,
} from "./provider";
import { renderBookingEmail } from "./render";
import { parseBookingEmailPayload, type BookingEmailJob } from "./schema";

const payload = {
  recipient_name: "Minta Mária",
  room_name: "1.Szoba-családi",
  start_at: "2026-10-05T07:00:00+00:00",
  end_at: "2026-10-05T08:00:00+00:00",
  use_type: "individual",
  booking_title: "Első konzultáció",
  scope: "single",
  affected_count: 1,
  first_start_at: "2026-10-05T07:00:00+00:00",
  last_end_at: "2026-10-05T08:00:00+00:00",
  performed_by_admin: false,
} as const;

const job: BookingEmailJob = {
  id: "a5000000-0000-0000-0000-000000000101",
  eventType: "booking.created",
  recipientEmail: "maria@example.com",
  payloadVersion: 1,
  payload,
};

describe("booking e-mail payload", () => {
  it("a DB snake_case payloadot szigorú v1 szerződéssé alakítja", () => {
    expect(parseBookingEmailPayload("booking.created", 1, payload)).toMatchObject({
      recipientName: "Minta Mária",
      roomName: "1.Szoba-családi",
      bookingTitle: "Első konzultáció",
      affectedCount: 1,
      performedByAdmin: false,
    });
  });

  it("elutasítja az ismeretlen payload-verziót", () => {
    expect(() => parseBookingEmailPayload("booking.created", 2, payload)).toThrow("Nem támogatott");
  });

  it("adatminimalizálásként elutasítja a megjegyzés és más ismeretlen mezőket", () => {
    expect(() => parseBookingEmailPayload("booking.created", 1, { ...payload, note: "titkos" }))
      .toThrow("Nem támogatott booking e-mail payload mező: note");
  });

  it("update esetén megköveteli a korábbi és új állapotot", () => {
    expect(() => parseBookingEmailPayload("booking.updated", 1, payload)).toThrow("korábbi és új állapot");
  });

  it("elutasítja a hibás időtartamot és scope-ot", () => {
    expect(() => parseBookingEmailPayload("booking.created", 1, { ...payload, end_at: payload.start_at }))
      .toThrow("időtartam");
    expect(() => parseBookingEmailPayload("booking.created", 1, { ...payload, scope: "all" }))
      .toThrow("scope");
  });
});

describe("magyar booking e-mail renderer", () => {
  it("egyedi create esetén mobilbarát text és HTML levelet készít", () => {
    const rendered = renderBookingEmail("booking.created", parseBookingEmailPayload("booking.created", 1, payload));
    expect(rendered.subject).toBe("Foglalás visszaigazolása – 1.Szoba-családi");
    expect(rendered.text).toContain("Kedves Minta Mária!");
    expect(rendered.text).toContain("Foglalás címe: Első konzultáció");
    expect(rendered.html).toContain('<meta name="viewport"');
    expect(rendered.html).toContain("A-Hely");
  });

  it("adminműveletet egyértelműen jelöl", () => {
    const parsed = parseBookingEmailPayload("booking.created", 1, { ...payload, performed_by_admin: true });
    const rendered = renderBookingEmail("booking.created", parsed);
    expect(rendered.text).toContain("adminisztrátora végezte a nevedben");
    expect(rendered.html).toContain("adminisztrátora végezte a nevedben");
  });

  it("update esetén az előző és az új állapotot is megjeleníti", () => {
    const updated = parseBookingEmailPayload("booking.updated", 1, {
      ...payload,
      room_name: "2.Szoba",
      booking_title: "Új cím",
      before: {
        room_name: "1.Szoba-családi", start_at: payload.start_at, end_at: payload.end_at,
        use_type: "individual", booking_title: "Régi cím",
      },
      after: {
        room_name: "2.Szoba", start_at: "2026-10-05T08:00:00Z", end_at: "2026-10-05T09:00:00Z",
        use_type: "individual", booking_title: "Új cím",
      },
    });
    const rendered = renderBookingEmail("booking.updated", updated);
    expect(rendered.text).toContain("Korábbi adatok:");
    expect(rendered.text).toContain("Új adatok:");
    expect(rendered.html).toContain("Régi cím");
    expect(rendered.html).toContain("Új cím");
  });

  it("sorozat és following scope esetén egy összefoglalót készít", () => {
    const series = parseBookingEmailPayload("booking.cancelled", 1, {
      ...payload,
      scope: "following",
      affected_count: 3,
      first_start_at: "2026-10-05T07:00:00Z",
      last_end_at: "2026-10-07T08:00:00Z",
      cancellation_reason: "Szabadság",
    });
    const rendered = renderBookingEmail("booking.cancelled", series);
    expect(rendered.subject).toContain("Foglalássorozat lemondva");
    expect(rendered.text).toContain("Érintett alkalmak: 3");
    expect(rendered.text).toContain("Lemondás oka: Szabadság");
  });

  it("HTML-escape-et alkalmaz minden dinamikus tartalomra", () => {
    const parsed = parseBookingEmailPayload("booking.created", 1, {
      ...payload,
      recipient_name: 'Mária <script> & "Társ"',
      room_name: "Szoba <img>",
    });
    const rendered = renderBookingEmail("booking.created", parsed);
    expect(rendered.html).toContain("Mária &lt;script&gt; &amp; &quot;Társ&quot;");
    expect(rendered.html).toContain("Szoba &lt;img&gt;");
    expect(rendered.html).not.toContain("<script>");
  });

  it("Europe/Budapest szerint helyesen kezeli a tavaszi DST-váltást", () => {
    const parsed = parseBookingEmailPayload("booking.created", 1, {
      ...payload,
      start_at: "2026-03-29T00:30:00Z",
      end_at: "2026-03-29T01:30:00Z",
      first_start_at: "2026-03-29T00:30:00Z",
      last_end_at: "2026-03-29T01:30:00Z",
    });
    const rendered = renderBookingEmail("booking.created", parsed);
    expect(rendered.text).toContain("01:30");
    expect(rendered.text).toContain("03:30");
  });
});

describe("booking e-mail provider adapter", () => {
  const config = {
    from: "A-Hely Foglalás <foglalas@a-hely.com>",
    replyTo: "foglalas@a-hely.com",
    messageIdDomain: "a-hely.com",
  };

  it("determinista Message-ID-t és biztonságos envelope-ot épít", () => {
    expect(buildOutboundBookingEmail(job, config)).toMatchObject({
      from: config.from,
      replyTo: config.replyTo,
      to: "maria@example.com",
      messageId: `<booking-${job.id}@a-hely.com>`,
    });
  });

  it("elutasítja a header injection kísérletet", () => {
    expect(() => buildOutboundBookingEmail({ ...job, recipientEmail: "maria@example.com\nBcc: x@example.com" }, config))
      .toThrow("címzett e-mail");
  });

  it("capture módban hálózat nélkül eltárolja a teljes renderelt üzenetet", async () => {
    const transport = createCaptureTransport();
    const result = await createBookingEmailSender(transport, config).send(job);
    expect(result).toEqual({ outcome: "captured" });
    expect(transport.captured).toHaveLength(1);
    expect(transport.captured[0].text).toContain("Minta Mária");
  });

  it("Nodemailer-kompatibilis kliensre változatlan envelope-ot továbbít", async () => {
    const sendMail = vi.fn().mockResolvedValue({ messageId: "provider-123" });
    const sender = createBookingEmailSender(createNodemailerCompatibleTransport({ sendMail }), config);
    await expect(sender.send(job)).resolves.toEqual({ outcome: "sent", providerMessageId: "provider-123" });
    expect(sendMail).toHaveBeenCalledOnce();
    expect(sendMail.mock.calls[0][0].to).toBe("maria@example.com");
  });

  it("provider Message-ID hiányában a determinisztikus Message-ID-t őrzi", async () => {
    const transport = createNodemailerCompatibleTransport({ sendMail: vi.fn().mockResolvedValue({}) });
    await expect(createBookingEmailSender(transport, config).send(job)).resolves.toEqual({
      outcome: "sent", providerMessageId: `<booking-${job.id}@a-hely.com>`,
    });
  });
});

describe("SMTP hibaosztályozás", () => {
  it("hálózati és 4xx hibát retryzhatónak minősít", () => {
    expect(classifyEmailTransportError({ code: "ETIMEDOUT", message: "secret host" })).toMatchObject({ disposition: "retry", code: "smtp_etimedout" });
    expect(classifyEmailTransportError({ responseCode: 451 })).toMatchObject({ disposition: "retry", code: "smtp_451" });
  });

  it("auth és 5xx hibát dead letternek minősít nyers provider válasz nélkül", () => {
    expect(classifyEmailTransportError({ code: "EAUTH", message: "password leaked" })).toEqual({
      disposition: "dead_letter", code: "smtp_auth", safeMessage: "Az SMTP hitelesítés sikertelen.",
    });
    const classified = classifyEmailTransportError({ responseCode: 550, response: "private recipient details" });
    expect(classified).toMatchObject({ disposition: "dead_letter", code: "smtp_550" });
    expect(JSON.stringify(classified)).not.toContain("private recipient details");
  });
});
