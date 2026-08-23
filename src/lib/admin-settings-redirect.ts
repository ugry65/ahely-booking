export function adminSettingsRedirectUrl(kind: "hiba" | "uzenet", message: string) {
  return `/admin/beallitasok?${kind}=${encodeURIComponent(message)}`;
}
