// GET /api/fixtures?d=YYYY-MM-DD -> TheSportsDB football fixtures for that day (proxied, cached 5 min)
export default async (req) => {
  const d = new URL(req.url).searchParams.get("d") || new Date().toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return new Response("Bad date", { status: 400 });
  try {
    const r = await fetch(`https://www.thesportsdb.com/api/v1/json/3/eventsday.php?d=${d}&s=Soccer`, { headers: { "user-agent": "needed-match" } });
    if (!r.ok) return Response.json({ events: [], error: `HTTP ${r.status}` }, { status: 502 });
    const j = await r.json();
    return Response.json({ events: j.events || [] }, { headers: { "cache-control": "public, max-age=300" } });
  } catch {
    return Response.json({ events: [], error: "unreachable" }, { status: 502 });
  }
};
export const config = { path: "/api/fixtures" };
