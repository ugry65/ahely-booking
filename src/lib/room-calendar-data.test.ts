import { beforeEach, describe, expect, it, vi } from "vitest";
const m=vi.hoisted(()=>({auth:vi.fn(),client:vi.fn(),rpc:vi.fn(),from:vi.fn(),requests:[] as Array<{name:string;args:unknown}>}));
vi.mock("server-only",()=>({}));vi.mock("./auth",()=>({requireActiveProfile:m.auth}));vi.mock("./supabase/server",()=>({createClient:m.client}));
import { loadRoomCalendar } from "./room-calendar-data";
import { parseRoomCalendarFilter } from "./room-calendar";
const rid="10000000-0000-0000-0000-000000000001",uid="20000000-0000-0000-0000-000000000001";
const room={room_id:rid,room_name:"Teszt",is_training_room:false,display_order:1};
const settings=[{key:"opening_time",value:"07:00"},{key:"closing_time",value:"22:00"},{key:"default_advance_booking_days",value:90},{key:"training_room_advance_days",value:10}];
function chain(result: unknown) { const q:Record<string,unknown>={};for(const k of ["select","in","eq","order","range","abortSignal","maybeSingle"])q[k]=vi.fn(()=>q);q.then=(r:(x:unknown)=>unknown)=>Promise.resolve(result).then(r);return q; }
const filter=(p:Record<string,string>={})=>parseRoomCalendarFilter({view:"month",room:rid,datum:"2026-10-13",...p},"2026-10-13");
beforeEach(()=>{vi.clearAllMocks();m.requests.length=0;m.auth.mockResolvedValue({id:uid,role:"user"});m.client.mockResolvedValue({rpc:m.rpc,from:m.from});m.from.mockImplementation((table:string)=>chain({error:null,data:table==="profiles"?{advance_booking_days_override:null}:settings}));m.rpc.mockImplementation((name:string,args:unknown)=>{m.requests.push({name,args});return chain({data:name==="list_bookable_rooms"?[room]:[],error:null,count:0});});});
describe("normal user occupancy data boundary",()=>{
  it("does not read data without an active user",async()=>{m.auth.mockRejectedValue(new Error("denied"));await expect(loadRoomCalendar(filter())).rejects.toThrow("denied");expect(m.client).not.toHaveBeenCalled();});
  it("rejects a forged unauthorized room before calendar reads",async()=>{await expect(loadRoomCalendar(filter({room:"30000000-0000-0000-0000-000000000001"}))).rejects.toThrow("hozzáférés");expect(m.requests.map(r=>r.name)).toEqual(["list_bookable_rooms"]);});
  it("uses only existing privacy-filtered calendar RPC, never admin reports or direct bookings",async()=>{await loadRoomCalendar(filter());expect(m.requests.map(r=>r.name)).toEqual(["list_bookable_rooms","list_calendar_bookings"]);expect(m.from.mock.calls.map(c=>c[0])).toEqual(["app_settings","profiles"]);});
  it("treats an empty room catalog as no authorized rooms",async()=>{m.rpc.mockImplementation(()=>chain({data:[],error:null,count:0}));expect((await loadRoomCalendar(filter({room:""}))).room).toBeUndefined();});
  it("fails closed on missing settings or row counts",async()=>{m.rpc.mockImplementation((n:string)=>chain({data:n==="list_bookable_rooms"?[room]:[],error:null,count:null}));await expect(loadRoomCalendar(filter())).rejects.toThrow("Hiányos");});
  it("fails closed on missing advance policy",async()=>{m.from.mockImplementation((t:string)=>chain({error:null,data:t==="profiles"?{advance_booking_days_override:null}:settings.slice(0,2)}));await expect(loadRoomCalendar(filter())).rejects.toThrow("beállítás");});
  it("paginates past a reduced server row limit without false availability",async()=>{
    let offset=0;
    m.rpc.mockImplementation((name:string)=>{
      if(name==="list_bookable_rooms")return chain({data:[room],error:null});
      const rows=Array.from({length:7},(_,i)=>({booking_id:`b${offset+i}`,room_id:rid,room_name:"Teszt",start_at:`2026-10-${String(offset+i+1).padStart(2,"0")}T12:00:00Z`,end_at:`2026-10-${String(offset+i+1).padStart(2,"0")}T13:00:00Z`,is_own:false,booker_display_name:null,booking_title:null,booker_color:null}));offset+=7;return chain({data:rows,error:null,count:14});
    });
    const result=await loadRoomCalendar(filter());expect(result.bookings).toHaveLength(14);expect(result.bookings.every(b=>b.booker_display_name===null&&b.booking_title===null)).toBe(true);expect(m.rpc).toHaveBeenCalledTimes(3);
  });
  it("does not return partial data when a later chunk fails",async()=>{let count=0;m.rpc.mockImplementation((n:string)=>{if(n==="list_bookable_rooms")return chain({data:[room],error:null});count++;return chain(count===1?{data:[],error:null,count:0}:{data:null,error:new Error("failed"),count:null});});await expect(loadRoomCalendar(filter({view:"list",from:"2026-10-01",to:"2026-11-30"}))).rejects.toThrow();});
});
