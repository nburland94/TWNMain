# Needed Tools — handoff for Codex

This is the current state of the project after Claude merged your last update (now round 36).
Build on **this** version — not an older folder — so nothing gets undone.

## Where to work, and how to send it back

- Repo: `github.com/nburland94/TWNMain`, branch `claude/continue-previous-task-q6ja0t` (the latest).
- When you're done, the owner uploads your folder to the `codex-updates` branch
  (`https://github.com/nburland94/TWNMain/upload/codex-updates`) — or push there directly.
- Keep the same folder layout (`Sources/`, `Resources/`, `Website/`, files at the top).
  Leave out `Needed Tools.app` and `Resources/bin/` (ffprobe — too big for GitHub).
- Add a short note of what you changed and what you tested (like your "Dark mode update.txt").

## What's what

| Area | Files |
|---|---|
| Mac app (Swift, AppKit + WKWebView pages) | `Sources/*.swift`, built by `Build-Needed-Tools.command` |
| Home, project page, Design | `Resources/shell/home.html`, `project.html`, `design.html` (+ `templates.js`) |
| Tools | `Resources/tools/{grab,vault,sort,shots,pay,credit}/index.html` |
| Dark mode | `Resources/shell/theme.js` — converts colours at runtime; rules that already say `[data-theme=dark]` are left alone |
| Glass | `Resources/shell/glass.js` — the website's nav glass on bars/panels, and a sliding lens on every `.seg` / `.seg2` switch. Loaded on every page before theme.js (`Shell.swift`, `themeSource`) |
| Phone app | **Source: `Website/vault/`**. The Mac serves an identical copy from `Resources/mobile/capture/`. Keep them identical (copy `index.html`, `app.js`, `jsQR.js`, `sw.js`, `mark.png`). The page tells where it's running from its path: `/capture/` = sent straight to the Mac (`DIRECT`), `/vault/` = website, syncs through Photos |
| Phone ↔ Mac | `Sources/Phone.swift` (Wi-Fi server: `/api/state`, `/api/upload` with receipts), `Sources/Pair.swift` (encrypted project list for the website), `Sources/PhotosInbox.swift` (files grabs from Photos) |
| Website | `Website/` (Netlify; `Website/netlify/functions/pair.mjs` is the pairing relay) |
| Notes for the owner | `READ-ME.txt` — add a round at the end for what you change |

## Please keep (decisions the owner made)

- **Nothing on the phone is deleted on its own.** The feed builds up; only grabs not yet on the Mac are sent.
  (The website version keeps a 1600px copy a day after Sync and lets the full file go; the Mac-served version keeps originals.)
- **Direct Wi-Fi counts a grab as sent only when the Mac confirms it saved it** (your receipts — keep them).
- **Design, "Use my stills": sample pictures first; the user's own pictures only after they confirm.**
- **The phone is Wi-Fi direct only** (round 35). Home › Your phone shows one QR code: the Mac-served page at `/capture/`.
  The website Vault, Browse and the Photos switches are not offered; From Photos is off by default; the website relay isn't started.
  The code for them is still there. A native iPhone app (`iPhone/NeededVault`) is the plan for grabbing away from home.
- **The running line** (name · project, page number) sits 5 units from the top edge on every page (`runner.top`/`inset`).
- **Templates**: A, B and C share 15 sections in one order (`C_SPEC` mirrors the A/B order). Pages are tagged
  `pg.tpl = {t, v, i}`; `tplSwitch()` flips a page between a/b/c; `cMakePage()` builds a C page. The eight arrangements
  are `C_LAYOUTS` in `layout()`, and the quick bar's **Arrange** applies them to any page (`arrangePage()`).
  Cinematography uses `feature` (the approved Option A).
  Round 37: A and B pages get the same place/arrangement controls. Arranging an A/B page sets `pg.tpl.arr = true`
  and keeps its letter (`isDesigned(p)` = A/B and not arranged); tapping the same letter rebuilds the designed page.
  On a laid-out (non-Free) page, Back/Front/Backward/Forward reorder `p.pics` (its place in the arrangement), not z.
- **The Mac's root page (`Resources/mobile/index.html`) only redirects to `/capture/`** — there is one phone app.
- **Home:** the colour dots and the quick actions share one line (`.line2`) under the filters.
- **Start again** (Vault, Grab, Sort) is a small orange pill under the tagline in `.brand`.
- **Claude / MCP (round 42).** `MCP/needed-mcp.swift` is a stdio MCP server (JSON-RPC, one message per line) built by the build script into
  `Contents/MacOS/needed-mcp` (a failed helper build doesn't stop the app). It forwards `tools/call` to the app's `Sources/ClaudeLink.swift`
  — `POST http://127.0.0.1:<port>/tool` with `Authorization: Bearer <token>`; port/token in `~/Library/Application Support/NeededTools/claude-link.json`
  (0600); loopback only; it opens the app if needed. Connect writes `mcpServers["needed-tools"] = {command: helper}` into
  `~/Library/Application Support/Claude/claude_desktop_config.json` (keeps a backup). Design work goes through the page's own engine:
  `window.__designBuild(spec)`, `__designWrite(o)`, `__designTemplates()` via `callAsyncJavaScript`; while building, `buildPool` makes the
  template deal from the user's stills instead of samples. Section names come from `C_SPEC` (the templates' real order — Story is 12th).
  Changes (tag_stills, build_treatment, write_page) respect `claudeChanges`. Voice = a chosen folder of .md/.txt, "voice" notes first, 60k chars.
- **Codex (round 43):** `ClaudeLink.connectCodex()` writes `[mcp_servers.needed-tools]` (command = the helper, args = [], startup_timeout_sec = 30,
  tool_timeout_sec = 300) into `~/.codex/config.toml`, removing any older copy of that section (and its sub-tables) first and keeping a backup;
  `disconnectCodex()` removes it. Status: `codexInstalled`, `codexConnected`, `codexElsewhere`. `copySettings()` puts an `mcpServers` JSON snippet
  on the clipboard for other MCP apps.
- **Top bar phone (round 42):** a small orange round button left of Sync (`#phoneBtn.phone`), green dot when on.
- **Crop in Design (round 40):** `pic.trim = {l,t,r,b}` (fractions of the picture kept). `aspOf(p)` is the picture's shape everywhere
  (layouts use it); `imgStyle(p, r)` draws a cropped picture in its frame, with Reframe (`pic.crop` x/y/z) inside the crop.
  The crop window is `openCrop(k)` (C, the Picture panel, the arrange bar, right-click). The vault file is never changed.
- **Licence = a Lemon Squeezy subscription (round 39, `Sources/Licence.swift`).** The owner builds the sign-in (Google / Apple /
  Microsoft) with you — keep it separate from the licence: sign-in says who they are, the licence says whether they've paid.
  - `Licence.status(tool:)` → `licensed`, `reason` ("none" | "expired" | "offline" | "tier"), `canBuy`, `subscription`, `plan`, `renews`.
    Each tool's gate reads it (`gateSay` in each tool's index.html); Home › account shows plan/renews/Manage.
  - Buttons call `buy` / `manage` / `recheck` (tools' `licence` handler) or `startSubscription` / `manageSubscription` (shell).
    `openCheckout` fills `checkout[email]` from the saved profile's `email` — so **when sign-in succeeds, save the signed-in email to
    `UserDefaults "profile"["email"]`** and the checkout is pre-filled.
  - The weekly check is `/v1/licenses/validate`; state lives in `licence-state.json` (signed). 14 days' grace offline.
  - `Resources/licence.json` stays `"provider": "off"` in the owner's own builds. Don't put the Lemon Squeezy **API key** in the app —
    only the public checkout link and IDs. Linking a signed-in email to a subscription (no key to paste) needs a small server
    (e.g. a Netlify function) holding the API key; not built yet.
  - Sign-in page (`Resources/shell/signin.html`, action `signIn` in Shell.swift) is still the placeholder; its key field isn't used —
    the key is entered on each tool's licence screen. After sign-in, you could show the licence screen if `status().licensed` is false.
- **iPhone app (round 38, `iPhone/NeededVault`)** is the approved phone design in SwiftUI (iOS 17). It keeps grabs on the phone
  (`Shared/Library.swift`: App Group `Grabs/` + `grabs.json`) and sends them to the Mac over Wi-Fi with the same API as `/capture/`
  (`Shared/MacLink.swift`: `GET /api/state`, `POST /api/upload?p&name&tags&phoneId` with `X-Key`; sent only on `{ok:true}`;
  `phoneId` = grab id so retries don't duplicate). Pairing reads the Mac's QR (`PairedMac.from`). Wi-Fi only (`allowsCellularAccess=false`),
  `NSAllowsLocalNetworking`, a background app-refresh send. It was written without a compiler in the cloud — build it in Xcode and fix
  anything it flags before changing behaviour.
- **Use my stills is per page** (`useMyStills()`; `useMyStills(true)` only from Export).
- **Glass** matches the website nav, in light and dark. Every sliding switch (`.seg`, `.seg2`, `.abseg`) gets the lens:
  **solid orange, white words, inside the pill with a 2px gap, no overshoot** — light and dark. The phone tab bar matches.
- Plain, friendly wording in the UI. Never mention Keynote. No personal email addresses in the product.
- Bundled sample pictures (`Resources/shell/samples`) are placeholders from other people's work — to be replaced before selling.
- The ninth template is shown as **Editorial** (its id stays `vogue` so older decks open). Don't use other companies' trademarks as names.
- **Licences:** `Resources/shell/acknowledgements.html` lists every third-party part (menu: Needed Tools › Acknowledgements).
  Add anything new you bundle there with its licence. Sort's ffprobe must stay an **LGPL** FFmpeg build (no `--enable-gpl`/`--enable-nonfree`).

## Testing that helps

- Pages run in any browser with a stub `window.webkit.messageHandlers.shell` — see how the pages call `call('action', {...})`.
- The phone app can be tested by serving `Website/` and `Resources/mobile/` locally; mock `/api/state` and `/api/upload` for the `/capture/` version.
- Say plainly what you could and couldn't test (e.g. a real iPhone → Mac transfer, the Swift build).
