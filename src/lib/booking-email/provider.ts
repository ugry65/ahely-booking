import { parseBookingEmailJob, type BookingEmailJob } from "./schema";
import { renderBookingEmail } from "./render";

export type OutboundEmailMessage = {
  from: string;
  replyTo: string;
  to: string;
  subject: string;
  text: string;
  html: string;
  messageId: string;
};

export type EmailDeliveryResult =
  | { outcome: "sent"; providerMessageId: string }
  | { outcome: "captured" };

export interface EmailTransport {
  send(message: OutboundEmailMessage): Promise<EmailDeliveryResult>;
}

export type BookingEmailSenderConfig = {
  from: string;
  replyTo: string;
  messageIdDomain: string;
};

export type NodemailerCompatibleClient = {
  sendMail(message: {
    from: string;
    replyTo: string;
    to: string;
    subject: string;
    text: string;
    html: string;
    messageId: string;
  }): Promise<{ messageId?: string }>;
};

function header(value: string, label: string): string {
  if (!value.trim() || /[\r\n]/.test(value)) throw new Error(`Érvénytelen ${label}.`);
  return value.trim();
}

function recipient(value: string): string {
  const normalized = header(value, "címzett e-mail").toLowerCase();
  if (normalized.length > 320 || normalized.indexOf("@") <= 0) throw new Error("Érvénytelen címzett e-mail.");
  return normalized;
}

function messageId(jobId: string, domain: string): string {
  const safeId = jobId.toLowerCase();
  const safeDomain = header(domain, "Message-ID domain").toLowerCase();
  if (!/^[a-z0-9-]+$/.test(safeId) || !/^[a-z0-9.-]+$/.test(safeDomain)) {
    throw new Error("Érvénytelen determinisztikus Message-ID alap.");
  }
  return `<booking-${safeId}@${safeDomain}>`;
}

export function buildOutboundBookingEmail(
  job: BookingEmailJob,
  config: BookingEmailSenderConfig,
): OutboundEmailMessage {
  const payload = parseBookingEmailJob(job);
  const rendered = renderBookingEmail(job.eventType, payload);
  return {
    from: header(config.from, "feladó"),
    replyTo: recipient(config.replyTo),
    to: recipient(job.recipientEmail),
    ...rendered,
    messageId: messageId(job.id, config.messageIdDomain),
  };
}

export function createBookingEmailSender(transport: EmailTransport, config: BookingEmailSenderConfig) {
  return {
    async send(job: BookingEmailJob): Promise<EmailDeliveryResult> {
      return transport.send(buildOutboundBookingEmail(job, config));
    },
  };
}

export function createNodemailerCompatibleTransport(client: NodemailerCompatibleClient): EmailTransport {
  return {
    async send(message) {
      const result = await client.sendMail(message);
      return { outcome: "sent", providerMessageId: result.messageId?.trim() || message.messageId };
    },
  };
}

export function createCaptureTransport(captured: OutboundEmailMessage[] = []): EmailTransport & { captured: OutboundEmailMessage[] } {
  return {
    captured,
    async send(message) {
      captured.push(structuredClone(message));
      return { outcome: "captured" };
    },
  };
}

export type ClassifiedEmailError = {
  disposition: "retry" | "dead_letter";
  code: string;
  safeMessage: string;
};

export function classifyEmailTransportError(error: unknown): ClassifiedEmailError {
  const source = error && typeof error === "object" ? error as Record<string, unknown> : {};
  const code = typeof source.code === "string" ? source.code.toUpperCase() : "UNKNOWN";
  const responseCode = typeof source.responseCode === "number" ? source.responseCode : undefined;

  if (["ETIMEDOUT", "ECONNRESET", "EAI_AGAIN", "ENETUNREACH", "ECONNREFUSED", "ESOCKET"].includes(code)) {
    return { disposition: "retry", code: `smtp_${code.toLowerCase()}`, safeMessage: "Átmeneti SMTP hálózati hiba." };
  }
  if (responseCode && responseCode >= 400 && responseCode < 500) {
    return { disposition: "retry", code: `smtp_${responseCode}`, safeMessage: "Az SMTP szerver átmenetileg nem fogadta el a levelet." };
  }
  if (code === "EAUTH" || responseCode === 535) {
    return { disposition: "dead_letter", code: "smtp_auth", safeMessage: "Az SMTP hitelesítés sikertelen." };
  }
  if (responseCode && responseCode >= 500 && responseCode < 600) {
    return { disposition: "dead_letter", code: `smtp_${responseCode}`, safeMessage: "Az SMTP szerver véglegesen elutasította a levelet." };
  }
  return { disposition: "dead_letter", code: "smtp_unknown", safeMessage: "Ismeretlen e-mail-küldési hiba." };
}
