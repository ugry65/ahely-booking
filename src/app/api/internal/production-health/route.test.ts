import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("production health anti-pause endpoint", () => {
  it("requires CRON_SECRET authorization", () => {
    const route = fs.readFileSync(path.join(process.cwd(), "src", "app", "api", "internal", "production-health", "route.ts"), "utf8");
    expect(route).toContain("process.env.CRON_SECRET");
    expect(route).toContain('request.headers.get("authorization")');
    expect(route).toContain("status: 401");
  });

  it("performs only a read against app_settings and returns safe status", () => {
    const route = fs.readFileSync(path.join(process.cwd(), "src", "app", "api", "internal", "production-health", "route.ts"), "utf8");
    expect(route).toContain('.from("app_settings").select("key").limit(1)');
    expect(route).not.toContain(".insert(");
    expect(route).not.toContain(".update(");
    expect(route).not.toContain(".delete(");
    expect(route).toContain("status: 503");
    expect(route).toContain("{ ok: true }");
  });

  it("schedules four daily production cron checks", () => {
    const config = fs.readFileSync(path.join(process.cwd(), "vercel.json"), "utf8");
    expect(config.match(/\/api\/internal\/production-health/g)?.length).toBe(4);
    expect(config).toContain('"15 0 * * *"');
    expect(config).toContain('"15 6 * * *"');
    expect(config).toContain('"15 12 * * *"');
    expect(config).toContain('"15 18 * * *"');
  });
});
