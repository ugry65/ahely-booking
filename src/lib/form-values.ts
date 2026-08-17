export function checkboxValue(formData: FormData, fieldName: string): boolean {
  return formData.getAll(fieldName).map(String).includes("true");
}
