"use client";

import { useState } from "react";
import { oneHourAfter } from "@/lib/booking-time";

type Props = {
  options: string[];
  initialStartTime: string;
  initialEndTime: string;
};

export function BookingTimeFields({ options, initialStartTime, initialEndTime }: Props) {
  const [startTime, setStartTime] = useState(initialStartTime);
  const [endTime, setEndTime] = useState(initialEndTime);

  return (
    <div className="form-row">
      <label>Kezdés
        <select
          name="startTime"
          required
          value={startTime}
          onChange={(event) => {
            const nextStart = event.target.value;
            setStartTime(nextStart);
            setEndTime(oneHourAfter(nextStart));
          }}
        >
          {options.slice(0, -2).map((time) => <option key={time} value={time}>{time}</option>)}
        </select>
      </label>
      <label>Befejezés
        <select name="endTime" required value={endTime} onChange={(event) => setEndTime(event.target.value)}>
          {options.slice(2).map((time) => <option key={time} value={time}>{time}</option>)}
        </select>
      </label>
    </div>
  );
}
