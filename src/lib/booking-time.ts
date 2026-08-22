const TIME_PATTERN = /^(?:[01]\\d|2[0-3]):[0-5]\\d$/;

export function oneHourAfter(startTime: string) {
  if (!TIME_PATTERN.test(startTime)) return startTime;
  const [hour, minute] = startTime.split(":").map(Number);
  const endMinute = Math.min(hour * 60 + minute + 60, 22 * 60);
  return `${String(Math.floor(endMinute / 60)).padStart(2, "0")}:${String(endMinute % 60).padStart(2, "0")}`;
}
