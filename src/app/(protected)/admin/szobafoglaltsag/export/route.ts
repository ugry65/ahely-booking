import { requireAdmin } from "@/lib/auth";
import { parseOccupancyFilter } from "@/lib/room-occupancy";
import { loadRoomOccupancy } from "@/lib/room-occupancy-data";
import { roomOccupancyXlsx } from "@/lib/room-occupancy-xlsx";

export async function GET(request: Request) {
  await requireAdmin();
  try {
    const params = Object.fromEntries(new URL(request.url).searchParams);
    const filter = parseOccupancyFilter(params);
    const data = await loadRoomOccupancy(filter, true);
    const bytes = roomOccupancyXlsx(data.bookings);
    return new Response(new Uint8Array(bytes).buffer, { headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="a-hely-szobafoglaltsag-${filter.from}_${filter.to}.xlsx"`,
      "Cache-Control": "private, no-store",
    } });
  } catch {
    return new Response("Az export nem sikerült. Ellenőrizd a szűrést és próbáld újra. Hiányos export nem készül.", {status: 400, headers: {"Cache-Control":"private, no-store"}});
  }
}
