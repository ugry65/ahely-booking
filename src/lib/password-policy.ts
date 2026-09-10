export const MIN_PASSWORD_LENGTH = 12;

export function validateNewPassword(password: string, confirmation: string) {
  if (password.length < MIN_PASSWORD_LENGTH) return "A jelszó legalább 12 karakter legyen.";
  if (password !== confirmation) return "A két jelszó nem egyezik.";
  return null;
}
