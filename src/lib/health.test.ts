import { describe, expect, it } from "vitest";

import { runHealthCheck } from "@/lib/health";

function clock(...values: number[]) {
  let index = 0;
  return () => values[Math.min(index++, values.length - 1)] ?? 0;
}

describe("runHealthCheck", () => {
  it("returns 200 when the database check succeeds", async () => {
    const result = await runHealthCheck(async () => true, clock(100, 127));

    expect(result).toEqual({
      status: 200,
      body: {
        ok: true,
        database: "ok",
        responseTimeMs: 27,
      },
    });
  });

  it("fails closed with 503 when the database check returns false", async () => {
    const result = await runHealthCheck(async () => false, clock(100, 109));

    expect(result).toEqual({
      status: 503,
      body: {
        ok: false,
        database: "error",
        responseTimeMs: 9,
      },
    });
  });

  it("does not expose database errors when the check throws", async () => {
    const result = await runHealthCheck(
      async () => {
        throw new Error("sensitive database detail");
      },
      clock(100, 115),
    );

    expect(result).toEqual({
      status: 503,
      body: {
        ok: false,
        database: "error",
        responseTimeMs: 15,
      },
    });
    expect(JSON.stringify(result)).not.toContain("sensitive database detail");
  });
});
