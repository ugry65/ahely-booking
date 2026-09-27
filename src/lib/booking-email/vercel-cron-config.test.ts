import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

type VercelConfig = {
  crons?: Array<{ path?: string; schedule?: string }>;
};

function readVercelConfig(): VercelConfig {
  return JSON.parse(readFileSync(join(process.cwd(), "vercel.json"), "utf8")) as VercelConfig;
}

describe("Vercel cron konfiguráció", () => {
  it("nem ütemezi a booking e-mail workert, amíg az értesítések ki vannak kapcsolva", () => {
    const config = readVercelConfig();
    expect(config.crons?.some((cron) => cron.path === "/api/internal/booking-email-worker")).toBe(false);
  });

  it("megtartja a production health négy napi futását", () => {
    const config = readVercelConfig();
    const healthCrons = config.crons?.filter((cron) => cron.path === "/api/internal/production-health") ?? [];
    expect(healthCrons).toEqual([
      { path: "/api/internal/production-health", schedule: "15 0 * * *" },
      { path: "/api/internal/production-health", schedule: "15 6 * * *" },
      { path: "/api/internal/production-health", schedule: "15 12 * * *" },
      { path: "/api/internal/production-health", schedule: "15 18 * * *" },
    ]);
  });
});
