export default function Home() {
  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui" }}>
      <h1>StatShot API</h1>
      <p>Sports alert backend for the StatShot iOS app.</p>
      <h2>Endpoints</h2>
      <ul>
        <li><code>POST /api/register</code> — Register device</li>
        <li><code>GET /api/scores</code> — All league scores</li>
        <li><code>GET /api/scores/[league]</code> — Scores by league</li>
        <li><code>GET /api/search?q=</code> — Search players/teams</li>
        <li><code>GET/POST /api/subscriptions</code> — Manage alert subscriptions</li>
        <li><code>PUT/DELETE /api/subscriptions/[id]</code> — Update/delete subscription</li>
        <li><code>GET /api/alerts?userId=</code> — Alert history</li>
      </ul>
    </main>
  );
}
