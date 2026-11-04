import { getStore } from "@netlify/blobs";

// GET  /api/channels  -> { channels: [...] }       (public)
// POST /api/channels  -> 200 if password is right   (used to unlock editing)
// PUT  /api/channels  -> saves the list             (needs x-admin-key header)
export default async (req) => {
  const store = getStore("needed-match");
  const key = process.env.ADMIN_KEY;
  const authed = key && req.headers.get("x-admin-key") === key;

  if (req.method === "GET") {
    const data = (await store.get("channels", { type: "json" })) || { channels: [] };
    return Response.json(data, { headers: { "cache-control": "no-store" } });
  }
  if (!authed) return new Response("Unauthorized", { status: 401 });
  if (req.method === "POST") return Response.json({ ok: true });
  if (req.method === "PUT") {
    let body;
    try { body = await req.json(); } catch { return new Response("Bad JSON", { status: 400 }); }
    if (!Array.isArray(body?.channels)) return new Response("Bad data", { status: 400 });
    const channels = body.channels.slice(0, 200)
      .map((c) => ({
        name: String(c?.name || "Channel").slice(0, 80),
        url: String(c?.url || "").slice(0, 2000),
        match: c?.match && typeof c.match === "object" ? c.match : {},
      }))
      .filter((c) => /^https?:\/\//i.test(c.url));
    await store.setJSON("channels", { channels, updated: Date.now() });
    return Response.json({ ok: true, count: channels.length });
  }
  return new Response("Method not allowed", { status: 405 });
};

export const config = { path: "/api/channels" };
