import { getStore } from "@netlify/blobs";

// GET /api/status -> { checked, status: { [url]: { on: bool, why: string } } }
// Probes each saved channel's HLS playlist from the server (no browser CORS limits).
// A channel is "on air" when its playlist loads, has segments, isn't a finished VOD,
// and its media sequence has moved since the last check (when we've seen it before).
const FRESH_MS = 30_000;      // reuse a result for 30s so many viewers don't hammer streams
const STALE_MS = 120_000;     // same media sequence for 2 min = frozen = off air

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

async function getText(url) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 6000);
  try {
    const r = await fetch(url, { signal: ctl.signal, headers: { "user-agent": UA }, redirect: "follow" });
    if (!r.ok) return { err: `HTTP ${r.status}` };
    return { text: await r.text(), url: r.url || url };
  } catch (e) {
    return { err: e.name === "AbortError" ? "timeout" : "unreachable" };
  } finally { clearTimeout(t); }
}

async function probe(url) {
  let res = await getText(url);
  if (res.err) return { on: false, why: res.err };
  if (!res.text.includes("#EXTM3U")) return { on: false, why: "not a playlist" };
  // master playlist -> follow first variant
  if (res.text.includes("#EXT-X-STREAM-INF")) {
    const lines = res.text.split(/\r?\n/);
    const i = lines.findIndex((l) => l.startsWith("#EXT-X-STREAM-INF"));
    const next = lines.slice(i + 1).find((l) => l && !l.startsWith("#"));
    if (!next) return { on: false, why: "empty master" };
    res = await getText(new URL(next.trim(), res.url).href);
    if (res.err) return { on: false, why: "variant " + res.err };
  }
  const segs = (res.text.match(/#EXTINF/g) || []).length;
  if (!segs) return { on: false, why: "no segments" };
  if (res.text.includes("#EXT-X-ENDLIST")) return { on: false, why: "ended" };
  const seq = +(/#EXT-X-MEDIA-SEQUENCE:(\d+)/.exec(res.text)?.[1] ?? -1);
  return { on: true, why: "live", seq };
}

export default async () => {
  const store = getStore("needed-match");
  const prev = (await store.get("status", { type: "json" })) || { checked: 0, status: {} };
  if (Date.now() - prev.checked < FRESH_MS) return Response.json(prev, { headers: { "cache-control": "no-store" } });

  const { channels = [] } = (await store.get("channels", { type: "json" })) || {};
  const now = Date.now();
  const status = {};
  await Promise.all(channels.slice(0, 60).map(async (c) => {
    const p = await probe(c.url);
    const old = prev.status[c.url];
    if (p.on && p.seq >= 0) {
      const moved = !old || old.seq !== p.seq;
      p.seqAt = moved ? now : old.seqAt;
      if (!moved && now - old.seqAt > STALE_MS) { p.on = false; p.why = "frozen"; }
    }
    status[c.url] = p;
  }));
  const out = { checked: now, status };
  await store.setJSON("status", out);
  return Response.json(out, { headers: { "cache-control": "no-store" } });
};

export const config = { path: "/api/status" };
