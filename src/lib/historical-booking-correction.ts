export function isHistoricalAdminEdit(isAdmin: boolean, mode: string, startAt: string | null | undefined, now = Date.now()): boolean {
  return isAdmin && mode === "edit" && Boolean(startAt) && new Date(startAt!).getTime() <= now;
}
