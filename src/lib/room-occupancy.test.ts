import { describe, expect, it } from "vitest";
import { filterQuery, freeIntervals, freeMatches, monday, parseOccupancyFilter, readAllPages, reportMonths, timeLabel, todayBudapest, visibleWeek, type OccupancyBooking } from "./room-occupancy";
import { roomOccupancyXlsx } from "./room-occupancy-xlsx";
const room = {id:"10000000-0000-0000-0000-000000000001",name:"Tréningterem",is_active:true};
function booking(start: string, end: string, patch: Partial<OccupancyBooking> = {}): OccupancyBooking {
  return {booking_id:"b",user_id:"u",user_name:"Teszt Foglaló",booking_date:"2026-10-08",room_name:room.name,booking_title:null,start_time:start,end_time:end,status:"active",...patch};
}
describe("szobafoglaltság szűrés",() => {
  it("includes the full calendar year and leap day",() => { expect(parseOccupancyFilter({from:"2024-01-01",to:"2024-12-31"}).to).toBe("2024-12-31"); });
  it("defaults to the current Budapest month, including December rollover",()=>{expect(parseOccupancyFilter({},"2026-12-08")).toMatchObject({from:"2026-12-01",to:"2026-12-31"});});
  it.each([{from:"2026-02-30"},{from:"2026-10-09",to:"2026-10-08"},{from:"2025-01-01",to:"2026-12-31"},{rooms:"not-a-uuid"},{user:"invalid"},{start:"14:10"},{start:"19:00",end:"14:00"},{duration:"30"},{week:"broken"},{page:"NaN"}])("rejects invalid filter %j",params=>expect(()=>parseOccupancyFilter(params,"2026-10-08")).toThrow());
  it("keeps Budapest dates across UTC midnight",()=>expect(todayBudapest(new Date("2026-10-07T22:30:00Z"))).toBe("2026-10-08"));
  it("keeps Monday weeks through both DST changes",()=>{ expect(monday("2026-03-29")).toBe("2026-03-23");expect(monday("2026-10-25")).toBe("2026-10-19"); });
  it("iterates cross-year months and preserves query filters when paging",()=>{expect(reportMonths("2025-12-28","2026-02-03")).toEqual(["2025-12-01","2026-01-01","2026-02-01"]);const f=parseOccupancyFilter({rooms:room.id,cancelled:"1"},"2026-10-08");expect(new URLSearchParams(filterQuery(f,{page:2})).get("rooms")).toBe(room.id);expect(visibleWeek(f)[0]).toBe("2026-10-05");});
});
describe("szabad idősáv",()=>{
  it("merges touching/overlapping occupancy and clips to the search window",()=>{expect(freeIntervals([booking("13:00","15:00"),booking("15:00","16:00"),booking("15:30","17:00"),booking("18:00","20:00")],"2026-10-08",room.name,840,1140)).toEqual([{start:1020,end:1080}]);});
  it("cancelled and other rooms/days do not block availability",()=>{expect(freeIntervals([booking("14:00","19:00",{status:"cancelled"}),booking("14:00","19:00",{room_name:"Másik"}),booking("14:00","19:00",{booking_date:"2026-10-09"})],"2026-10-08",room.name,840,1140)).toEqual([{start:840,end:1140}]);});
  it("uses all owners and finds the exact minimum duration",()=>{const f=parseOccupancyFilter({},"2026-10-08");expect(freeMatches([booking("14:00","17:00",{user_id:"someone-else"})],"2026-10-08",room,f,{start:420,end:1320})).toEqual([{start:1020,end:1140}]);});
  it("does not mistake multiple short gaps for one long gap",()=>{const f=parseOccupancyFilter({},"2026-10-08");expect(freeMatches([booking("15:00","18:00")],"2026-10-08",room,f,{start:420,end:1320})).toEqual([]);});
  it("whole-afternoon and inactive/outside-opening searches fail closed",()=>{const f={...parseOccupancyFilter({},"2026-10-08"),whole:true};expect(freeMatches([booking("18:00","19:00")],"2026-10-08",room,f,{start:420,end:1320})).toEqual([]);expect(freeMatches([],"2026-10-08",{...room,is_active:false},f,{start:420,end:1320})).toEqual([]);expect(freeMatches([],"2026-10-08",room,f,{start:900,end:1320})).toEqual([]);});
});
describe("complete RPC pagination",()=>{
  it("reads beyond the Supabase default 1000 row cap",async()=>{const data=Array.from({length:1250},(_,i)=>i);expect(await readAllPages(async(from,to)=>({data:data.slice(from,to+1),error:null,count:data.length}))).toHaveLength(1250);});
  it("continues if the server caps individual responses below the requested page size",async()=>{const data=Array.from({length:750},(_,i)=>i);await expect(readAllPages(async(from,to)=>({data:data.slice(from,Math.min(to+1,from+250)),error:null,count:data.length}))).resolves.toHaveLength(750);});
  it("discards partial/error/count-changing results",async()=>{await expect(readAllPages(async()=>({data:[],error:null,count:1}))).rejects.toThrow();await expect(readAllPages(async()=>({data:[],error:new Error("secret"),count:0}))).rejects.toThrow("Hiányos");await expect(readAllPages(async()=>({data:[],error:null,count:20001}))).rejects.toThrow("Túl sok");});
});
it("Excel is a ZIP workbook with escaped inline text, not executable formulas",()=>{const bytes=roomOccupancyXlsx([booking("14:00","16:00",{booking_title:"=HYPERLINK(\"x\") <&>",status:"cancelled"})]);expect(Array.from(bytes.slice(0,4))).toEqual([80,75,3,4]);const xml=new TextDecoder().decode(bytes);expect(xml).toContain("&lt;&amp;&gt;");expect(xml).toContain('t="inlineStr"');expect(xml).not.toContain("<f>");expect(xml).toContain("Törölt");expect(xml).toContain('autoFilter ref="A1:G2"');expect(timeLabel(840)).toBe("14:00");});
