// GET /api/fixtures?d=YYYY-MM-DD -> today's football across major competitions (ESPN public scoreboard),
// normalised to the fields the page uses. Cached 2 min.
const LEAGUES = [
  "eng.1", "eng.2", "eng.fa", "eng.league_cup", "uefa.champions", "uefa.europa", "uefa.europa.conf",
  "esp.1", "ita.1", "ger.1", "fra.1", "sco.1", "ned.1", "por.1", "usa.1", "fifa.world", "uefa.nations",
];

export default async (req) => {
  const d = new URL(req.url).searchParams.get("d") || new Date().toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return new Response("Bad date", { status: 400 });
  const ymd = d.replace(/-/g, "");
  const results = await Promise.all(LEAGUES.map(async (lg) => {
    try {
      const r = await fetch(`https://site.api.espn.com/apis/site/v2/sports/soccer/${lg}/scoreboard?dates=${ymd}`);
      if (!r.ok) return [];
      const j = await r.json();
      const league = j.leagues?.[0]?.name || lg;
      return (j.events || []).map((e) => {
        const comp = e.competitions?.[0] || {};
        const home = comp.competitors?.find((c) => c.homeAway === "home") || {};
        const away = comp.competitors?.find((c) => c.homeAway === "away") || {};
        const st = e.status?.type || {};
        const started = st.state && st.state !== "pre";
        return {
          idEvent: "espn-" + e.id,
          strHomeTeam: home.team?.displayName || "TBC",
          strAwayTeam: away.team?.displayName || "TBC",
          strHomeTeamBadge: home.team?.logo || null,
          strAwayTeamBadge: away.team?.logo || null,
          strLeague: league,
          strTimestamp: e.date,
          intHomeScore: started ? home.score ?? null : null,
          intAwayScore: started ? away.score ?? null : null,
          strStatus: st.state === "pre" ? "Not Started" : st.state === "post" ? "FT" : (e.status?.type?.shortDetail || "Live"),
        };
      });
    } catch { return []; }
  }));
  return Response.json({ events: results.flat() }, { headers: { "cache-control": "public, max-age=120" } });
};
export const config = { path: "/api/fixtures" };
