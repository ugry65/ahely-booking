import { timingSafeEqual } from "node:crypto";

import {
  disabledBookingEmailWorkerSummary,
  type BookingEmailMode,
  type BookingEmailWorkerSummary,
} from "./worker";

export type BookingEmailWorkerRuntime = {
  mode: BookingEmailMode;
  run?: () => Promise<BookingEmailWorkerSummary>;
};

export type BookingEmailWorkerRouteDependencies = {
  getCronSecret: () => string;
  createRuntime: () => BookingEmailWorkerRuntime;
};

function authorized(request: Request, expectedSecret: string): boolean {
  if (!expectedSecret || /[\r\n]/.test(expectedSecret)) return false;
  const provided = request.headers.get("authorization");
  if (!provided?.startsWith("Bearer ")) return false;
  const providedToken = Buffer.from(provided.slice("Bearer ".length), "utf8");
  const expectedToken = Buffer.from(expectedSecret, "utf8");
  return providedToken.length === expectedToken.length && timingSafeEqual(providedToken, expectedToken);
}

function response(body: object, status: number): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

export async function handleBookingEmailWorkerRequest(
  request: Request,
  dependencies: BookingEmailWorkerRouteDependencies,
): Promise<Response> {
  let cronSecret: string;
  try {
    cronSecret = dependencies.getCronSecret();
  } catch {
    return response({ error: "worker_not_configured" }, 503);
  }

  if (!authorized(request, cronSecret)) {
    return response({ error: "unauthorized" }, 401);
  }

  let runtime: BookingEmailWorkerRuntime;
  try {
    runtime = dependencies.createRuntime();
  } catch {
    return response({ error: "worker_not_configured" }, 503);
  }

  if (runtime.mode === "disabled") {
    return response(disabledBookingEmailWorkerSummary(), 200);
  }
  if (!runtime.run) {
    return response({ error: "worker_not_configured" }, 503);
  }

  try {
    return response(await runtime.run(), 200);
  } catch {
    return response({ error: "worker_failed" }, 500);
  }
}
