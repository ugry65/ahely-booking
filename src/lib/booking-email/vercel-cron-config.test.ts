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
  it("percenként ütemezi a booking e-mail workert", () => {
    const config = readVercelConfig();
    expect(config.crons).toContainEqual({
      path: "/api/internal/booking-email-worker",
      schedule: "* * * * *",
    });
  });

  it("nem hozza vissza a régi production-health időzítést", () => {
    const config = readVercelConfig();
    expect(config.crons?.filter(cron => cron.path === "/api/internal/production-health")).toEqual([]);
  });
});
