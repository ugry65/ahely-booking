export const DUPLICATE_EMAIL_MESSAGE = "Már létezik felhasználó ezzel az e-mail-címmel.";
export const GENERIC_AUTH_CREATE_ERROR_MESSAGE = "A felhasználó létrehozása nem sikerült. Próbáld újra később.";

type AuthCreateError = {
  code?: string;
} | null;

const DUPLICATE_AUTH_CODES = new Set(["email_exists", "user_already_exists"]);

export function generateTemporaryPassword(randomUuid: () => string = () => crypto.randomUUID()) {
  return `${randomUuid().replaceAll("-", "")}Aa1!`;
}

export function authCreateErrorMessage(error: AuthCreateError) {
  return error?.code && DUPLICATE_AUTH_CODES.has(error.code)
    ? DUPLICATE_EMAIL_MESSAGE
    : GENERIC_AUTH_CREATE_ERROR_MESSAGE;
}
