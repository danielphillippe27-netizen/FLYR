function App() {
  return (
    <main className="legacy-shell">
      <section className="legacy-card">
        <p className="legacy-eyebrow">Legacy Dashboard Retired</p>
        <h1>FLYR now lives in the `FLYR-PRO` web app.</h1>
        <p className="legacy-copy">
          This Vite dashboard has been intentionally shut down because its auth,
          workspace, leaderboard, leads, stats, and CRM behavior no longer match
          the active product.
        </p>
        <p className="legacy-copy">
          Use the current Next.js app in `FLYR-PRO` for any web work going
          forward.
        </p>
        <div className="legacy-actions">
          <a href="https://www.flyrpro.app" className="legacy-button">
            Open Production App
          </a>
          <code className="legacy-command">cd ../FLYR-PRO</code>
        </div>
      </section>
    </main>
  )
}

export default App
