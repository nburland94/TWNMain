// GET /api/facts?id=espn-123&lg=uefa.champions -> scorers, cards and team stats (ESPN match summary). Cached 30s.
const WANT = [
  ["possessionPct", "Possession", true], ["totalShots", "Shots"], ["shotsOnTarget", "Shots on target"],
  ["wonCorners", "Corners"], ["saves", "Saves"], ["foulsCommitted", "Fouls"], ["offsides", "Offsides"],
  ["yellowCards", "Yellow cards"], ["redCards", "Red cards"], ["passPct", "Pass accuracy", true],
];
function kindOf(t = "") {
  t = t.toLowerCase();
  if (t.includes("own goal")) return "og";
  if (t.includes("missed") || t.includes("saved")) return null;
  if (t.includes("goal") || t.includes("penalty - scored") || t.includes("scored")) return "goal";
  if (t.includes("red card") || t.includes("second yellow")) return "red";
  if (t.includes("yellow")) return "yellow";
  if (t.includes("substitution")) return "sub";
  return null;
}
export default async (req) => {
  const u = new URL(req.url);
  const id = (u.searchParams.get("id") || "").replace(/^espn-/, "");
  const lg = u.searchParams.get("lg") || "";
  if (!/^\d+$/.test(id) || !/^[a-z0-9._]+$/i.test(lg)) return new Response("Bad request", { status: 400 });
  try {
    const r = await fetch(`https://site.api.espn.com/apis/site/v2/sports/soccer/${lg}/summary?event=${id}`);
    if (!r.ok) return Response.json({ error: `HTTP ${r.status}` }, { status: 502 });
    const j = await r.json();
    const comp = j.header?.competitions?.[0] || {};
    const teams = (comp.competitors || []).map((c) => ({
      side: c.homeAway, id: String(c.team?.id ?? c.id ?? ""), name: c.team?.displayName, short: c.team?.abbreviation,
      logo: c.team?.logos?.[0]?.href || c.team?.logo || null, score: c.score ?? null,
    }));
    const sideOf = (teamId) => teams.find((t) => t.id === String(teamId))?.side || null;
    const by = {};
    (j.boxscore?.teams || []).forEach((t, i) => {
      const side = sideOf(t.team?.id) || t.homeAway || (i === 0 ? "home" : "away");
      by[side] = Object.fromEntries((t.statistics || []).map((s) => [s.name, s.displayValue]));
    });
    const stats = WANT.filter(([k]) => by.home?.[k] != null || by.away?.[k] != null)
      .map(([k, label, pct]) => ({ label, home: by.home?.[k] ?? "0", away: by.away?.[k] ?? "0", pct: !!pct }));
    const events = (j.keyEvents || []).map((e) => {
      const kind = kindOf(e.type?.text || e.text);
      if (!kind) return null;
      let who = (e.participants || []).map((p) => p.athlete?.displayName).filter(Boolean);
      if (kind === "sub") {
        // "Substitution, Team. A replaces B." -> [on, off]
        const m = /([^.,]+?)\s+replaces\s+([^.,]+?)(?:\s+because[^.]*)?\.?$/i.exec(e.text || e.shortText || "");
        if (m) who = [m[1].trim(), m[2].trim()];
      }
      return { kind, min: e.clock?.displayValue || "", side: sideOf(e.team?.id), who };
    }).filter(Boolean);
    const lineups = (j.rosters || []).map((t, i) => {
      const side = sideOf(t.team?.id) || t.homeAway || (i === 0 ? "home" : "away");
      const p = (r) => ({
        n: r.jersey || "", name: r.athlete?.displayName || r.athlete?.shortName || "",
        pos: r.position?.abbreviation || "", on: !!r.subbedIn, off: !!r.subbedOut,
        place: +r.formationPlace || 99,
      });
      const list = (t.roster || []).map((r) => ({ ...p(r), starter: !!r.starter }));
      return {
        side, formation: t.formation || "",
        starters: list.filter((x) => x.starter).sort((a, b) => a.place - b.place),
        bench: list.filter((x) => !x.starter),
      };
    }).filter((l) => l.starters.length || l.bench.length);
    return Response.json({
      status: comp.status?.type?.shortDetail || "", state: comp.status?.type?.state || "",
      teams, stats, events, lineups,
      venue: j.gameInfo?.venue?.fullName || null,
    }, { headers: { "cache-control": "public, max-age=30" } });
  } catch {
    return Response.json({ error: "unreachable" }, { status: 502 });
  }
};
export const config = { path: "/api/facts" };
