// Needed Mobile Vault — the pairing relay. Your Mac leaves its project list here; your phone
// picks it up, so new projects reach the phone without scanning again.
// What's kept is scrambled on the Mac with a key that only lives in the QR code (after the #,
// which browsers never send to a server) — this function, and Netlify, only ever see gibberish.
// One small record per pairing: { box, w (a hash of the Mac's write secret), at }.
import { getStore } from "@netlify/blobs";

const ID = /^[A-Za-z0-9_-]{16,64}$/;
const sha = async s => Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))).toString("base64url");
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export default async req => {
  const id = new URL(req.url).searchParams.get("id") || "";
  if (!ID.test(id)) return json({ error: "bad id" }, 400);
  const store = getStore("needed-pairs");
  if (req.method === "GET") {
    const v = await store.get(id, { type: "json" });
    return v ? json({ box: v.box, at: v.at }) : json({ error: "not yet" }, 404);
  }
  if (req.method === "PUT" || req.method === "POST") {
    let body; try { body = await req.json(); } catch { return json({ error: "bad body" }, 400); }
    const box = typeof body.box === "string" ? body.box : "", w = typeof body.w === "string" ? body.w : "";
    if (!box || box.length > 64000 || w.length < 16) return json({ error: "bad body" }, 400);
    const h = await sha(w), cur = await store.get(id, { type: "json" });
    if (cur && cur.w !== h) return json({ error: "not yours" }, 403);        // only the Mac that made it can change it
    await store.setJSON(id, { box, w: h, at: Date.now() });
    return json({ ok: true });
  }
  return json({ error: "method" }, 405);
};

export const config = { path: "/api/pair" };
