import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { CALENDAR_COLOR_PALETTE } from "@/lib/calendar-colors";

describe("self-service calendar color", () => {
  it("offers exactly 20 approved colors without requiring uniqueness", () => {
    expect(CALENDAR_COLOR_PALETTE).toHaveLength(20);
    expect(new Set(CALENDAR_COLOR_PALETTE.map((item) => item.value)).size).toBe(20);
  });

  it("loads and submits the current calendar color from Adataim", () => {
    const page = fs.readFileSync(path.join(process.cwd(), "src", "app", "(protected)", "adataim", "page.tsx"), "utf8");
    const form = fs.readFileSync(path.join(process.cwd(), "src", "app", "(protected)", "adataim", "profile-form.tsx"), "utf8");
    expect(page).toContain("tax_number,calendar_color");
    expect(form).toContain("CALENDAR_COLOR_PALETTE.map");
    expect(form).toContain('name="calendarColor"');
    expect(form).toContain("updateOwnCalendarColor");
    expect(form).toContain("Ugyanazt a színt mások is választhatják.");
  });

  it("validates the palette in the server action and persists through a dedicated RPC", () => {
    const actions = fs.readFileSync(path.join(process.cwd(), "src", "app", "(protected)", "adataim", "actions.ts"), "utf8");
    expect(actions).toContain("CALENDAR_COLOR_VALUES.includes");
    expect(actions).toContain('supabase.rpc("update_own_calendar_color"');
    expect(actions).toContain('revalidatePath("/foglalasok")');
  });

  it("keeps backend validation and audit logging in the migration", () => {
    const migration = fs.readFileSync(path.join(process.cwd(), "supabase", "migrations", "20260928162000_user_calendar_color_self_service.sql"), "utf8");
    expect(migration).toContain("security definer");
    expect(migration).toContain("where id = auth.uid() and is_active");
    expect(migration).toContain("Érvénytelen naptárszín.");
    expect(migration).toContain("profile.calendar_color_updated");
    expect(migration).toContain("grant execute on function public.update_own_calendar_color(text, uuid) to authenticated");
  });
});
