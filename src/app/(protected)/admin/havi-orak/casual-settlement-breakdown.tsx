import type { MonthlyBookingDetailWithMonth } from "@/lib/monthly-hours";

const CASUAL_USERS = new Set(["Alkalmi Csoport", "Alkalmi Egyéni"]);
function hours(value: number) { return value.toLocaleString("hu-HU", { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
function huf(value: number) { return value.toLocaleString("hu-HU") + " Ft"; }

type CasualGroup = {
  month: string;
  userName: string;
  title: string;
  bookings: MonthlyBookingDetailWithMonth[];
  hours: number;
  due: number;
};

export function CasualSettlementBreakdown({ details }: { details: MonthlyBookingDetailWithMonth[] }) {
  const groups = new Map<string, CasualGroup>();
  for (const row of details) {
    if (!CASUAL_USERS.has(row.user_name)) continue;
    const title = row.booking_title?.trim() || "Névtelen alkalmi foglalás";
    const key = [row.month, row.user_name, title.toLocaleLowerCase("hu")].join("|");
    const existing = groups.get(key) ?? { month: row.month, userName: row.user_name, title, bookings: [], hours: 0, due: 0 };
    existing.bookings.push(row);
    existing.hours += Number(row.total_hours);
    existing.due += Number(row.amount_huf);
    groups.set(key, existing);
  }

  const byCollector = new Map<string, CasualGroup[]>();
  for (const group of groups.values()) {
    const key = `${group.month}|${group.userName}`;
    byCollector.set(key, [...(byCollector.get(key) ?? []), group]);
  }
  if (!groups.size) return null;

  return <section className="card wide-card stack">
    <div>
      <p className="eyebrow">Staging előnézet</p>
      <h2>Alkalmi foglalók elszámolása</h2>
      <p className="muted">Azonos foglalási cím ugyanabban a hónapban összevonva. A foglaló sora lenyitható az egyes alkalmakra. A Fizetve mező ebben az első staging körben még csak a tervezett helyét mutatja, pénzügyi adatot nem módosít.</p>
    </div>
    {[...byCollector.entries()].map(([collectorKey, collectorGroups]) => {
      const [month, userName] = collectorKey.split("|");
      const collectorHours = collectorGroups.reduce((sum, item) => sum + item.hours, 0);
      const collectorDue = collectorGroups.reduce((sum, item) => sum + item.due, 0);
      return <details className="casual-settlement-collector" open key={collectorKey}>
        <summary><strong>{userName}</strong> · {month} · {hours(collectorHours)} óra · {huf(collectorDue)}</summary>
        <div className="table-scroll"><table>
          <thead><tr><th>Foglaló</th><th>Alkalom</th><th>Óra</th><th>Fizetendő</th><th>Befizetve</th><th>Tartozás</th><th>Fizetve</th></tr></thead>
          <tbody>{collectorGroups.sort((a,b)=>a.title.localeCompare(b.title,"hu")).map((group) => <tr key={group.title}>
            <td><details><summary>{group.title}</summary><div className="casual-booking-lines">{group.bookings.sort((a,b)=>a.booking_date.localeCompare(b.booking_date)).map((booking)=><div key={booking.booking_id}><span>{booking.booking_date} · {booking.room_name} · {booking.start_time.slice(0,5)}–{booking.end_time.slice(0,5)}</span><strong>{huf(Number(booking.amount_huf))}</strong></div>)}</div></details></td>
            <td>{group.bookings.length}</td><td>{hours(group.hours)}</td><td>{huf(group.due)}</td>
            <td className="muted">—</td><td>{huf(group.due)}</td>
            <td><label className="payment-preview-check"><input type="checkbox" disabled aria-label={`${group.title} fizetve`} /> <span className="muted">terv</span></label></td>
          </tr>)}</tbody>
        </table></div>
      </details>;
    })}
  </section>;
}
