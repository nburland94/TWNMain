// POST /api/identify  { image: <base64 jpeg>, fixtures: [{id,home,away,league}] }  (needs x-admin-key)
// Asks Claude which of today's fixtures the frame shows. Returns { fixtureId|null, confidence, seen }.
export default async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const admin = process.env.ADMIN_KEY;
  if (!admin || req.headers.get("x-admin-key") !== admin) return new Response("Unauthorized", { status: 401 });
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return Response.json({ error: "no-key" }, { status: 503 });

  let body;
  try { body = await req.json(); } catch { return new Response("Bad JSON", { status: 400 }); }
  const image = String(body?.image || "");
  const fixtures = Array.isArray(body?.fixtures) ? body.fixtures.slice(0, 80) : [];
  if (!image || image.length > 2_000_000 || !fixtures.length) return new Response("Bad data", { status: 400 });

  const list = fixtures.map((f) => `${f.id}: ${f.home} vs ${f.away} (${f.league})`).join("\n");
  const prompt = `This is a single frame from a live football (soccer) TV broadcast.
Look at the on-screen score graphic, team names or 3-letter abbreviations, kit colours, crests, captions and pitch-side boards.
Which ONE of these fixtures is being shown?

${list}

Reply with ONLY a JSON object, no other text:
{"fixtureId": "<id from the list>" or null, "confidence": <0 to 1>, "seen": "<the score/teams text you can read, max 40 chars>"}
Use null if it is adverts, a studio/pundit shot, a replay of another match, a different sport, or you cannot tell.`;

  const models = [process.env.SCAN_MODEL, "claude-haiku-5-5", "claude-sonnet-5-5"].filter(Boolean);
  let lastErr = "";
  for (const model of models) {
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model,
        max_tokens: 150,
        messages: [{ role: "user", content: [
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: image } },
          { type: "text", text: prompt },
        ] }],
      }),
    });
    if (!r.ok) {
      lastErr = `${model}: api ${r.status} ${(await r.text()).slice(0, 200)}`;
      if (r.status === 404 || r.status === 400) continue;   // unknown model -> try the next one
      return Response.json({ error: lastErr }, { status: 502 });
    }
    const j = await r.json();
    const text = j.content?.map((c) => c.text || "").join("") || "";
    const m = /\{[\s\S]*\}/.exec(text);
    const out = m ? JSON.parse(m[0]) : {};
    const valid = fixtures.some((f) => f.id === out.fixtureId);
    return Response.json({
      fixtureId: valid ? out.fixtureId : null,
      confidence: Math.max(0, Math.min(1, +out.confidence || 0)),
      seen: String(out.seen || "").slice(0, 60),
      model,
    });
  } catch (e) {
    lastErr = `${model}: ${e.message || "failed"}`;
  }
  }
  return Response.json({ error: lastErr || "failed" }, { status: 502 });
};

export const config = { path: "/api/identify" };
