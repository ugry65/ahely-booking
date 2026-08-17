const AUTH_REDIRECT_ALLOWLIST = new Set([
  "/foglalasok",
  "/jelszo-visszaallitas",
]);

export function getSafeAuthRedirectPath(requestedPath: string | null): string {
  if (requestedPath && AUTH_REDIRECT_ALLOWLIST.has(requestedPath)) {
    return requestedPath;
  }

  return "/foglalasok";
}
