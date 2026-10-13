import { beforeEach, describe, expect, it, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
const m=vi.hoisted(()=>({load:vi.fn()}));
vi.mock("@/lib/room-calendar-data",()=>({loadRoomCalendar:m.load}));
vi.mock("./room-calendar.module.css",()=>({default:Object.fromEntries(["page","heading","tabs","filters","filterFields","full","month","grid","weekday","day","selected","today","outside","bar","free","more","limit","row"].map(s=>[s,s]))}));
import { RoomCalendarView } from "./room-calendar-view";
const rid="10000000-0000-0000-0000-000000000001";
const rooms=[{room_id:rid,room_name:"Teszt szoba",is_training_room:false,display_order:1}];
const data={rooms,room:rooms[0],bookings:[{booking_id:"b1",room_id:rid,room_name:"Teszt szoba",start_at:"2026-10-13T08:00:00Z",end_at:"2026-10-13T10:00:00Z",is_own:false,booker_display_name:null,booking_title:null,booker_color:null},{booking_id:"b2",room_id:rid,room_name:"Teszt szoba",start_at:"2026-10-13T13:00:00Z",end_at:"2026-10-13T15:00:00Z",is_own:true,booker_display_name:"Teszt Foglaló",booking_title:"Saját cím",booker_color:null}],opening:{start:420,end:1320},defaultDays:90,trainingDays:10,override:null,profile:{role:"user",id:"test"}};
beforeEach(()=>{vi.clearAllMocks();vi.setSystemTime(new Date("2026-10-13T07:00:00Z"));m.load.mockResolvedValue(data);});
async function html(params:Record<string,string | undefined>={}){return renderToStaticMarkup(await RoomCalendarView({params:{view:"month",datum:"2026-10-13",room:rid,...params}}));}
describe("monthly/list user interface",()=>{
  it("shows the month, all real days, chosen day's bookings and free slots with handoff",async()=>{const markup=await html();expect(markup).toContain("2026. október");expect(markup.match(/class="day/g)?.length).toBe(31);expect(markup).toContain("Saját foglalás");expect(markup).toContain("Foglalt");expect(markup).toContain("17:00–22:00 szabad");expect(markup).toContain("new=1");expect(markup).toContain('name="room"');});
  it("opens the daily booking calendar directly for every day in the month",async()=>{const markup=await html();const links=[...markup.matchAll(/<a[^>]*class="day[^"]*"[^>]*href="([^"]+)"/g)].map(m=>m[1]);expect(links).toHaveLength(31);expect(links[12]).toBe(`/foglalasok?datum=2026-10-13&amp;room=${rid}`);expect(links.every(href=>href.startsWith("/foglalasok?datum=")&&!href.includes("view=month"))).toBe(true);});
  it("includes empty days in the free list and keeps the requested period",async()=>{const markup=await html({view:"list",kind:"free",from:"2026-10-14",to:"2026-10-15"});expect(markup).toContain("2 találat");expect(markup).toContain("07:00–22:00 szabad");});
  it("shows only bookings in the booking list and no free-interval claims",async()=>{const markup=await html({view:"list",kind:"bookings"});expect(markup).toContain("2 találat");expect(markup).not.toContain("17:00–22:00 szabad");});
  it("never shows a free interval if loading fails",async()=>{m.load.mockRejectedValue(new Error("Hiányos adatok"));const markup=await html();expect(markup).toContain('role="alert"');expect(markup).not.toContain('class="bar"');expect(markup).not.toContain("szabad</p>");});
  it("renders no calendar for a user without permitted rooms",async()=>{m.load.mockResolvedValue({...data,rooms:[],room:undefined});expect(await html()).toContain("Nincs foglalható helyiséged");});
  it("creates an internal visual fixture when explicitly requested",async()=>{
    if(!process.env.ROOM_CALENDAR_PREVIEW)return;
    const root=process.env.ROOM_CALENDAR_PREVIEW;
    mkdirSync(root,{recursive:true});
    const css=["src/app/globals.css","src/app/skedda-mobile.css","src/app/(protected)/foglalasok/calendar-booking-actions.css","src/app/(protected)/foglalasok/room-calendar.module.css"].map(path=>readFileSync(path,"utf8").replace(/:global\(([^)]+)\)/g,"$1")).join("\n");
    for(const [name,params] of Object.entries({month:{},list:{view:"list",kind:"free",from:"2026-10-13",to:"2026-10-31"},bookings:{view:"list",kind:"bookings",from:"2026-10-13",to:"2026-10-31"}})) {
      const markup=await html(params);
      writeFileSync(`${root}/${name}.html`,`<!doctype html><html lang="hu"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>A-Hely teszt megjelenés</title><style>${css}</style><main><nav class="desktop-app-nav" aria-label="Főmenü"><a href="/foglalasok">Foglalási naptár</a><a href="/foglalasaim">Foglalásaim</a><a href="/adataim">Adataim</a></nav>${markup}</main></html>`);
    }
  });
});
