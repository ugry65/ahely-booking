export function passwordRecoveryRedirect(siteUrl: string | undefined) {
  const normalized = siteUrl?.trim().replace(/\/$/, "");
  return normalized ? `${normalized}/auth/confirm` : null;
}
