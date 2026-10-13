import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";

const m = vi.hoisted(() => ({ admin: vi.fn(), rpc: vi.fn() }));
vi.mock("@/lib/auth", () => ({ requireAdmin: m.admin }));
vi.mock("@/lib/supabase/server", () => ({ createClient: async () => ({ rpc: m.rpc }) }));
vi.mock("./actions", () => ({ setCentralPricing: vi.fn(), setTrainingRoomRate: vi.fn() }));
import PricingAdminPage from "./page";

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-13T20:54:58Z"));
  m.rpc.mockImplementation(async (name: string) => name === "admin_list_pricing_rules"
    ? { data: [], error: null }
    : { data: [{ settlement_month: "2026-10-01", already_closed: false }], error: null });
});
afterEach(() => vi.useRealTimers());
const html = async () => renderToStaticMarkup(await PricingAdminPage({ searchParams: Promise.resolve({}) }));

describe("pricing date UI", () => {
  it("sets both date inputs to the open month start and verifies closure as admin", async () => {
    const markup = await html();
    expect(m.admin).toHaveBeenCalledOnce();
    expect(m.rpc).toHaveBeenCalledWith("admin_monthly_settlement_close_preview", { p_month: "2026-10-01" });
    expect(markup.match(/min="2026-10-01"/g)).toHaveLength(2);
    expect(markup.match(/value="2026-10-01"/g)).toHaveLength(2);
    expect(markup).toContain("a hónap már megtörtént foglalásainak díját is érintheti");
  });
  it("moves both controls past a closed month", async () => {
    m.rpc.mockImplementation(async (name: string) => name === "admin_list_pricing_rules"
      ? { data: [], error: null }
      : { data: [{ settlement_month: "2026-10-01", already_closed: true }], error: null });
    const markup = await html();
    expect(markup.match(/min="2026-11-01"/g)).toHaveLength(2);
    expect(markup).toContain("Az aktuális hónap már lezárt");
  });
  it.each([
    { data: null, error: { message: "RPC failed" } },
    { data: [], error: null },
    { data: [{ settlement_month: "2026-09-01", already_closed: false }], error: null },
    { data: [{ settlement_month: "2026-10-01", already_closed: null }], error: null },
  ])("fails closed for unknown or invalid month state (%j)", async (state) => {
    m.rpc.mockImplementation(async (name: string) => name === "admin_list_pricing_rules"
      ? { data: [], error: null } : state);
    const markup = await html();
    expect(markup).toContain("A hónap lezárási állapota nem ellenőrizhető");
    expect(markup.match(/<button[^>]*disabled=""/g)).toHaveLength(2);
  });
});
