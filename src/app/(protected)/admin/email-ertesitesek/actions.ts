"use server";

import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/auth";
import { createBookingEmailWorkerRuntime } from "@/lib/booking-email/server";

function monitorUrl(kind: "uzenet" | "hiba", message: string): string {
  const params = new URLSearchParams({ [kind]: message });
  return `/admin/email-ertesitesek?${params.toString()}`;
}

export async function runBookingEmailCapture() {
  await requireAdmin();

  let runtime;
  try {
    runtime = createBookingEmailWorkerRuntime();
  } catch {
    redirect(monitorUrl("hiba", "A capture worker konfigurációja hibás vagy hiányos."));
  }

  if (runtime.mode !== "capture" || !runtime.run) {
    redirect(monitorUrl("hiba", "A kézi feldolgozás kizárólag capture módban engedélyezett."));
  }

  let summary;
  try {
    summary = await runtime.run();
  } catch {
    redirect(monitorUrl("hiba", "A capture worker futása nem fejeződött be."));
  }

  if (summary.mode !== "capture" || summary.sent !== 0) {
    redirect(monitorUrl("hiba", "A capture worker biztonsági ellenőrzése meghiúsult."));
  }

  redirect(monitorUrl(
    "uzenet",
    `Capture kész: ${summary.claimed} claimelt, ${summary.captured} rögzített, ${summary.retry} retry, ${summary.deadLetter} végleg hibás.`,
  ));
}
