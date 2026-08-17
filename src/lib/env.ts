export function requireEnv(name: string): string {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Hiányzó kötelező környezeti változó: ${name}`);
  }

  return value;
}
