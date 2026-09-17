export type HealthStatusBody = {
  ok: boolean;
  database: "ok" | "error";
  responseTimeMs: number;
};

export type HealthStatusResult = {
  status: 200 | 503;
  body: HealthStatusBody;
};

export async function runHealthCheck(
  checkDatabase: () => Promise<boolean>,
  now: () => number = Date.now,
): Promise<HealthStatusResult> {
  const startedAt = now();

  try {
    const databaseOk = await checkDatabase();
    const responseTimeMs = Math.max(0, now() - startedAt);

    if (!databaseOk) {
      return {
        status: 503,
        body: {
          ok: false,
          database: "error",
          responseTimeMs,
        },
      };
    }

    return {
      status: 200,
      body: {
        ok: true,
        database: "ok",
        responseTimeMs,
      },
    };
  } catch {
    return {
      status: 503,
      body: {
        ok: false,
        database: "error",
        responseTimeMs: Math.max(0, now() - startedAt),
      },
    };
  }
}
