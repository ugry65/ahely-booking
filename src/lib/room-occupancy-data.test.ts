import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(()=>({admin:vi.fn(),client:vi.fn(),rpc:vi.fn(),from:vi.fn(),requests:[] as Array<{name:string; args:Record<string,unknown>}>}));
vi.mock("server-only",()=>({}));
vi.mock("./auth",()=>({requireAdmin:mocks.admin}));
vi.mock("./supabase/server",()=>({createClient:mocks.client}));
import { loadRoomOccupancy } from "./room-occupancy-data";
import { parseOccupancyFilter } from "./room-occupancy";
import { GET } from "../app/(protected)/admin/szobafoglaltsag/export/route";
const rid="10000000-0000-0000-0000-000000000001", uid="20000000-0000-0000-0000-000000000001";
function chain(result: unknown) {
  const q: Record<string,unknown> = {};
  for (const method of ["select","order","in","gte","lte","range","abortSignal"]) q[method]=vi.fn(()=>q);
  q.then=(resolve: (x:unknown)=>unknown)=>Promise.resolve(result).then(resolve);
  return q;
}
beforeEach(()=>{
  vi.clearAllMocks();mocks.requests.length=0;mocks.admin.mockResolvedValue({role:"admin"});
  mocks.client.mockResolvedValue({from:mocks.from,rpc:mocks.rpc});
  mocks.from.mockImplementation((table:string)=>chain({error:null,data:table==="rooms"?[{id:rid,name:"Tréningterem",is_active:true}]:table==="profiles"?[{id:uid,first_name:"Teszt",last_name:"Foglaló"}]:[{key:"opening_time",value:"07:00"},{key:"closing_time",value:"22:00"}]}));
  mocks.rpc.mockImplementation((name:string,args:Record<string,unknown>)=>{mocks.requests.push({name,args});return chain({data:[{booking_id:`${name}-${args.p_month ?? args.p_end_month}`,user_id:uid,user_name:"Foglaló Teszt",booking_date:"2026-10-08",room_name:"Tréningterem",start_time:"14:00:00",end_time:"16:00:00",booking_title:"Teszt"}],error:null,count:1});});
});
describe("admin read-only data boundary",()=>{
  it("does not reach the database if admin authorization fails",async()=>{mocks.admin.mockRejectedValue(new Error("unauthorized"));await expect(loadRoomOccupancy(parseOccupancyFilter({}))).rejects.toThrow("unauthorized");expect(mocks.client).not.toHaveBeenCalled();});
  it("reuses only existing admin RPCs, and includes cancelled rows only in the list",async()=>{const data=await loadRoomOccupancy(parseOccupancyFilter({from:"2026-10-01",to:"2026-10-31",rooms:rid,user:uid,cancelled:"1"}));expect(data.bookings.map(b=>b.status)).toEqual(["cancelled","active"]);expect(mocks.requests).toEqual([{name:"admin_monthly_active_booking_details",args:{p_month:"2026-10-01",p_user_id:uid}},{name:"admin_cancellation_details",args:{p_end_month:"2026-10-01",p_months:1,p_user_id:uid}}]);expect(mocks.from.mock.calls.map(c=>c[0])).not.toContain("bookings");});
  it("ignores owner and cancelled filters for weekly availability",async()=>{await loadRoomOccupancy(parseOccupancyFilter({from:"2026-10-01",to:"2026-10-31",view:"week",user:uid,cancelled:"1"},"2026-10-08"));expect(mocks.requests).toHaveLength(1);expect(mocks.requests[0].args.p_user_id).toBeNull();});
  it("rejects unknown room and does not call a booking RPC",async()=>{await expect(loadRoomOccupancy(parseOccupancyFilter({rooms:"30000000-0000-0000-0000-000000000001"}))).rejects.toThrow("szoba");expect(mocks.rpc).not.toHaveBeenCalled();});
  it("fails closed if a later report request fails",async()=>{mocks.rpc.mockImplementationOnce(()=>chain({data:[],error:new Error("internal"),count:null}));await expect(loadRoomOccupancy(parseOccupancyFilter({}))).rejects.toThrow("Hiányos");});
  it("export checks authorization and never returns partial workbook",async()=>{mocks.rpc.mockImplementation(()=>chain({data:null,error:new Error("secret-value"),count:null}));const response=await GET(new Request("http://localhost/admin/szobafoglaltsag/export?from=2026-10-01&to=2026-10-31"));expect(response.status).toBe(400);expect(response.headers.get("cache-control")).toBe("private, no-store");expect(await response.text()).not.toContain("secret-value");});
  it("exports the full list with no-store and Excel type",async()=>{const response=await GET(new Request("http://localhost/admin/szobafoglaltsag/export?from=2026-10-01&to=2026-10-31"));expect(response.status).toBe(200);expect(response.headers.get("content-type")).toContain("spreadsheetml");expect(mocks.admin).toHaveBeenCalled();expect((await response.arrayBuffer()).byteLength).toBeGreaterThan(1000);});
});
