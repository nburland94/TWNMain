# Needed Tools — handoff for Codex

This is the current state of the project after Claude merged your last update (round 34).
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
- **Home › Your phone shows both**: the website Vault (anywhere) and Wi-Fi (Send to Mac / Browse the vault).
- **The running line** (name · project, page number) sits 5 units from the top edge on every page (`runner.top`/`inset`).
- **Templates**: A, B and C. C = `cDoc()` in design.html; the eight arrangements are `C_LAYOUTS` in `layout()`.
  Story comes after the visual pages. Cinematography uses `feature` (the approved Option A).
- **Glass** matches the website nav, in light and dark. Every sliding switch gets the lens.
- Plain, friendly wording in the UI. Never mention Keynote. No personal email addresses in the product.
- Bundled sample pictures (`Resources/shell/samples`) are placeholders from other people's work — to be replaced before selling.

## Testing that helps

- Pages run in any browser with a stub `window.webkit.messageHandlers.shell` — see how the pages call `call('action', {...})`.
- The phone app can be tested by serving `Website/` and `Resources/mobile/` locally; mock `/api/state` and `/api/upload` for the `/capture/` version.
- Say plainly what you could and couldn't test (e.g. a real iPhone → Mac transfer, the Swift build).
