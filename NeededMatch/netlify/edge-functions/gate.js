// Password gate for the whole site. Set VIEW_KEY in Netlify env vars to turn it on.
// Correct password -> HttpOnly cookie for 30 days. No VIEW_KEY -> site is open.
const COOKIE = "nm_view";

async function token(key) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("needed-match:" + key));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const page = (msg = "") => `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Needed Match</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0}body{font-family:Inter,-apple-system,system-ui,sans-serif;min-height:100vh;display:grid;place-items:center;background:#F3F0EA;color:#17140F;padding:20px}
body::before{content:"";position:fixed;inset:-20%;z-index:-1;background:radial-gradient(40% 45% at 18% 12%,rgba(255,150,80,.38),transparent 70%),radial-gradient(35% 40% at 88% 92%,rgba(140,170,255,.22),transparent 70%)}
form{width:min(380px,100%);padding:30px;border-radius:24px;background:rgba(255,255,255,.6);border:1px solid rgba(255,255,255,.85);backdrop-filter:blur(30px) saturate(170%);-webkit-backdrop-filter:blur(30px) saturate(170%);box-shadow:0 20px 50px -20px rgba(60,40,20,.25)}
.b{display:flex;align-items:center;gap:10px;font-weight:700;margin-bottom:22px}.b i{width:34px;height:26px;border-radius:8px;background:#17140F;color:#fff;display:grid;place-items:center;font-style:normal;font-size:10px}
h1{font-size:22px;letter-spacing:-.02em;margin-bottom:6px}p{font-size:13px;color:rgba(23,20,15,.6);margin-bottom:18px}
input{width:100%;height:48px;padding:0 14px;border-radius:12px;border:1px solid rgba(23,20,15,.1);background:rgba(255,255,255,.85);font:inherit;font-size:15px;outline:none}
input:focus{border-color:#FF6A1A;box-shadow:0 0 0 4px rgba(255,106,26,.14)}
button{margin-top:12px;width:100%;height:48px;border:0;border-radius:12px;background:#FF6A1A;color:#fff;font:inherit;font-weight:600;font-size:15px;cursor:pointer;box-shadow:0 6px 18px -6px rgba(255,106,26,.7)}
.e{color:#C2341B;font-size:13px;margin-top:10px;min-height:18px}
</style></head><body><form method="POST" action="/__login">
<div class="b"><i>TWN</i>Needed Match</div><h1>Enter password</h1><p>This screen is private.</p>
<input type="password" name="pw" autofocus required autocomplete="current-password"><button>Watch</button><div class="e">${msg}</div>
</form></body></html>`;

export default async (req, context) => {
  const key = Netlify.env.get("VIEW_KEY");
  if (!key) return context.next();
  const want = await token(key);
  const url = new URL(req.url);

  if (url.pathname === "/__login" && req.method === "POST") {
    const form = await req.formData().catch(() => null);
    if (form && form.get("pw") === key) {
      return new Response(null, { status: 303, headers: {
        location: "/",
        "set-cookie": `${COOKIE}=${want}; Path=/; Max-Age=2592000; HttpOnly; Secure; SameSite=Lax`,
      } });
    }
    return new Response(page("Wrong password"), { status: 401, headers: { "content-type": "text/html; charset=utf-8" } });
  }

  const has = (req.headers.get("cookie") || "").split(/;\s*/).some((c) => c === `${COOKIE}=${want}`);
  if (has) return context.next();
  if (url.pathname.startsWith("/api/")) return new Response("Locked", { status: 401 });
  return new Response(page(), { status: 401, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
};

export const config = { path: "/*" };
