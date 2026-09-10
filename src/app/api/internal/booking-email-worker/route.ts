import {
  createBookingEmailWorkerRuntime,
  getBookingEmailCronSecret,
} from "@/lib/booking-email/server";
import { handleBookingEmailWorkerRequest } from "@/lib/booking-email/worker-route";

export const runtime = "nodejs";

async function runWorker(request: Request): Promise<Response> {
  return handleBookingEmailWorkerRequest(request, {
    getCronSecret: getBookingEmailCronSecret,
    createRuntime: createBookingEmailWorkerRuntime,
  });
}

// A Vercel Cron GET kérést küld; a POST kézi, védett preflight futtatáshoz marad elérhető.
export const GET = runWorker;
export const POST = runWorker;
