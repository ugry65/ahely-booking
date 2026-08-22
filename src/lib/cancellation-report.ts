export const CANCELLATION_PERIODS = [1, 3, 6, 12] as const;
export type CancellationPeriod = (typeof CANCELLATION_PERIODS)[number];

export type CancellationSummaryRow = {
  user_id: string;
  user_name: string;
  total_bookings: number;
  cancelled_count: number;
  cancelled_hours: number | string;
  user_cancelled_count: number;
  user_cancelled_hours: number | string;
  cancellation_rate: number | string;
};

export type CancellationDetailRow = {
  booking_id: string;
  user_id: string;
  user_name: string;
  booking_date: string;
  room_name: string;
  start_time: string;
  end_time: string;
  cancelled_hours: number | string;
  cancelled_at: string;
  minutes_before_start: number;
  cancellation_reason: string | null;
  cancelled_by_user: boolean;
  cancelled_by_name: string;
};

export function cancellationPeriod(value: string | undefined): CancellationPeriod {
  const parsed = Number(value);
  return CANCELLATION_PERIODS.includes(parsed as CancellationPeriod) ? parsed as CancellationPeriod : 3;
}

export function leadTimeLabel(minutes: number): string {
  const absolute = Math.abs(minutes);
  const days = Math.floor(absolute / 1440);
  const hours = Math.floor((absolute % 1440) / 60);
  const mins = absolute % 60;
  const prefix = minutes < 0 ? "kezdés után " : "";
  if (days > 0) return `${prefix}${days} nap ${hours} óra`;
  if (hours > 0) return `${prefix}${hours} óra ${mins} perc`;
  return `${prefix}${mins} perc`;
}
