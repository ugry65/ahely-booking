export default function OfflinePage() {
  return (
    <main className="auth-shell">
      <section className="card stack" aria-live="polite">
        <p className="eyebrow">A-Hely foglalás</p>
        <h1>Nincs internetkapcsolat</h1>
        <p>
          A foglalási rendszer csak online állapotban használható. Offline módban nem jelenítünk meg
          korábban betöltött foglalási adatot, és nem indítunk foglalást vagy más módosítást.
        </p>
        <p className="muted">Kapcsolódj újra az internethez, majd frissítsd az oldalt.</p>
      </section>
    </main>
  );
}
