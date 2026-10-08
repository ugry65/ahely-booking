"use client";
import { useState } from "react";
import { monday, shiftDay, timeLabel, type OccupancyFilter, type ReportRoom } from "@/lib/room-occupancy";
import styles from "./occupancy.module.css";

type Props = { filter: OccupancyFilter; rooms: ReportRoom[]; users: Array<{ id: string; first_name: string; last_name: string }>; today: string };
export function OccupancyFilters({ filter, rooms, users, today }: Props) {
  const [from, setFrom] = useState(filter.from), [to, setTo] = useState(filter.to);
  const [view, setView] = useState(filter.view);
  const [selected, setSelected] = useState(filter.roomIds.length ? filter.roomIds : rooms.filter(r => r.is_active).map(r => r.id));
  function preset(kind: "week" | "month" | "year") {
    const start = kind === "year" ? `${today.slice(0, 4)}-01-01` : kind === "month" ? `${today.slice(0, 7)}-01` : monday(today);
    const end = kind === "year" ? `${today.slice(0, 4)}-12-31` : kind === "month" ? shiftDay(shiftDay(start, 32).slice(0, 7) + "-01", -1) : shiftDay(start, 6);
    setFrom(start); setTo(end);
  }
  return <form method="get" className={`card wide-card stack ${styles.filters}`}>
    <div className={styles.presets}><span>Gyors időszak:</span><button type="button" className="secondary" onClick={() => preset("week")}>Ezen a héten</button><button type="button" className="secondary" onClick={() => preset("month")}>Ebben a hónapban</button><button type="button" className="secondary" onClick={() => preset("year")}>Idén</button></div>
    <div className={styles.fields}>
      <label>Dátumtól<input type="date" name="from" value={from} onChange={e => setFrom(e.target.value)} required /></label>
      <label>Dátumig<input type="date" name="to" value={to} onChange={e => setTo(e.target.value)} required /></label>
      <label>Nézet<select name="view" value={view} onChange={e => setView(e.target.value as "list" | "week")}><option value="list">Foglalási lista</option><option value="week">Heti foglaltság és szabad időpontok</option></select></label>
      {view === "list" ? <label>Foglaló<select name="user" defaultValue={filter.userId ?? ""}><option value="">Összes foglaló</option>{users.map(u => <option key={u.id} value={u.id}>{u.last_name} {u.first_name}</option>)}</select></label> : null}
    </div>
    <fieldset className={styles.roomSet}><legend>Szobák</legend><div className={styles.presets}><button type="button" className="secondary" onClick={() => setSelected(rooms.filter(r => r.is_active).map(r => r.id))}>Összes aktív</button><button type="button" className="secondary" onClick={() => setSelected([])}>Kijelölés törlése</button></div>
      <div className={styles.rooms}>{rooms.map(r => <label key={r.id}><input type="checkbox" checked={selected.includes(r.id)} onChange={e => setSelected(e.target.checked ? [...selected, r.id] : selected.filter(id => id !== r.id))} />{r.name}{!r.is_active ? " (inaktív)" : ""}</label>)}</div>
    </fieldset><input type="hidden" name="rooms" value={selected.join(",")} />
    {view === "list" ? <label className={styles.check}><input type="checkbox" name="cancelled" value="1" defaultChecked={filter.cancelled} />Törölt foglalások is</label> : <>
      <div className={styles.fields}><label>Szabad idő keresése ettől<input type="time" name="start" defaultValue={timeLabel(filter.start)} step="1800" required /></label><label>Eddig<input type="time" name="end" defaultValue={timeLabel(filter.end)} step="1800" required /></label><label>Szükséges egybefüggő idő<select name="duration" defaultValue={filter.duration}>{Array.from({length: 29}, (_,i) => (i+2)*30).map(m => <option key={m} value={m}>{(m/60).toLocaleString("hu-HU")} óra</option>)}</select></label></div>
      <label className={styles.check}><input type="checkbox" name="whole" value="1" defaultChecked={filter.whole} />A teljes megadott idősáv legyen szabad</label>
      <p className="muted">A foglaltság és a szabad idő keresése mindig minden foglalót figyelembe vesz. Inaktív szobát nem ajánlunk szabad időpontként.</p>
    </>}
    {!selected.length ? <p className="message error" role="status">Jelölj ki legalább egy szobát.</p> : null}
    <div><button disabled={!selected.length}>Lekérdezés</button></div>
  </form>;
}
