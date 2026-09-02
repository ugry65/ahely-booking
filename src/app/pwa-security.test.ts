import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

import manifest from "./manifest";

describe("PWA security baseline", () => {
  it("is installable and starts in the booking application", () => {
    const value = manifest();

    expect(value.display).toBe("standalone");
    expect(value.start_url).toBe("/foglalasok");
    expect(value.icons).toHaveLength(2);
  });

  it("does not implement business-data caching or background writes", () => {
    const serviceWorker = fs.readFileSync(path.join(process.cwd(), "public", "sw.js"), "utf8");

    expect(serviceWorker).toContain('const OFFLINE_URL = "/offline"');
    expect(serviceWorker).toContain('url.pathname.startsWith("/api/")');
    expect(serviceWorker).toContain('url.pathname.startsWith("/auth/")');
    expect(serviceWorker).toContain('request.mode === "navigate"');
    expect(serviceWorker).not.toContain("sync");
    expect(serviceWorker).not.toContain("indexedDB");
  });
});
