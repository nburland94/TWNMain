# Message for Codex — finish your task, then bring it onto the latest Needed Tools

Hi Codex. The owner (Nathan) has kept building Needed Tools with Claude while you were working on your current task. **Please finish what you're doing first**, then apply it on top of the latest code described here — without losing any of the newer work below. Read `HANDOFF-FOR-CODEX.md` too: it lists the decisions the owner made that must stay.

## Where the latest code is

- GitHub: `nburland94/TWNMain`, branch **`codex-updates`** (the same as `claude/continue-previous-task-q6ja0t`). Latest: **Round 43** ("Connect to Codex (OpenAI) on this Mac…") and this message.
- Or the zip Nathan gives you: `NeededTools-for-Codex-round43.zip` — same files.
- Your last work that came into this code was the upload merged at `079639d` ("Bring in the Codex update"). Everything since then is new to you.

## How to bring your work across (please follow this order)

1. **Finish your current task** where you are, and note which files you changed (`git diff --stat` against where you started, or list them).
2. **Start from the latest code**: `git fetch origin codex-updates` and make a new branch from it, e.g. `codex/<your-task-name>`. (Working from the zip: unzip `NeededTools-for-Codex-round43.zip` and work in that folder.)
3. **Re-apply your changes onto it** — merge or cherry-pick your commits, or port them by hand file by file. Do **not** overwrite whole files with your older copies: most files below changed a lot since your base. Where you and the newer work both touched the same lines, **keep both behaviours**; if they truly conflict, keep the newer behaviour and write down what you'd change (see "When unsure").
4. **Check it**:
   - JavaScript/HTML: open the pages, no console errors. The owner's Playwright habit: load `Resources/shell/design.html`, `home.html`, `chrome.html` and each `Resources/tools/*/index.html` with a stubbed `window.webkit.messageHandlers` bridge.
   - Swift (Mac): `Build-Needed-Tools.command` must still compile `Sources/*.swift` and, separately, `MCP/needed-mcp.swift`.
   - iPhone app: `iPhone/NeededVault` should still generate and build in Xcode (`Make-Needed-Vault-iPhone.command`).
5. **Write it up**: add a short section at the end of `READ-ME.txt` (plain words, like the rounds before) and a note in `HANDOFF-FOR-CODEX.md` for anything the next person must keep.
6. **Send it back**: push your branch (`codex/<your-task-name>`) and open a pull request into `codex-updates` — or, if you can't push, give Nathan a zip of the changed files with their folder paths so he can upload them. Tell him in one paragraph what changed and anything he should test.

## What changed since your last merge (so you don't undo it)

| Round | What | Main files |
|---|---|---|
| 33–35 | Website-style glass and the orange sliding lens on every switch; dark-mode text; C templates like A/B; the Arrange quick-bar button; Use my stills per page; phone is Wi-Fi direct only | `Resources/shell/glass.js`, `theme.js`, `design.html`, `welcome.html`, `signin.html`, `home.html` |
| 36 | Vogue shown as **Editorial** (id `vogue` kept); Acknowledgements page and licence files; ffprobe must stay an LGPL build | `templates.js`, `acknowledgements.html`, `Resources/shell/licences/`, `Build-Needed-Tools.command` |
| 37 | The Mac's old phone page (`Resources/mobile/index.html`) only redirects to `/capture/`; **Start again** is a small orange pill under the tagline in Vault, Grab, Sort; A and B pages get Where the pictures go + Arrangements (`pg.tpl.arr`, `isDesigned()`); Back/Front reorder pictures on laid-out pages; Home: colours + quick actions on one line | `Resources/mobile/index.html`, `Resources/tools/{vault,grab,sort}/index.html`, `design.html`, `home.html` |
| 38 | **iPhone app rebuilt** in the approved design: grabs kept on the phone (offline), sent to the Mac over Wi-Fi with the `/capture/` API and receipts | everything in `iPhone/NeededVault` (old `Shared/Vault.swift` removed; new `Library.swift`, `MacLink.swift`, `Sheets.swift`, `Capture.swift`) |
| 39 | **Subscriptions** (Lemon Squeezy): free month at checkout, weekly key check with 14 days offline, renew/upgrade screens, plans per tool (`tiers`) | `Sources/Licence.swift`, each tool's Swift file (`buy`/`manage`/`recheck`), each `Resources/tools/*/index.html` gate (`gateSay`), `home.html`, `Resources/licence.json` (stays `"provider": "off"`) |
| 40–41 | **Crop in Design**: `pic.trim`, `aspOf()`, `imgStyle()`, the crop window (`openCrop`); double-click a picture opens Crop; Reframe stays on the bar/panel/right-click | `design.html` |
| 42 | **Claude (MCP)**: `MCP/needed-mcp.swift` (stdio MCP server, built into `Contents/MacOS/needed-mcp`), `Sources/ClaudeLink.swift` (loopback link + tools), Design hooks `__designBuild`/`__designWrite`/`__designTemplates`, account panel "Claude · Codex"; section names come from `C_SPEC` (Story is 12th); top-bar Phone is a small orange round button left of Sync | `MCP/`, `Sources/ClaudeLink.swift`, `Sources/Shell.swift`, `design.html`, `home.html`, `chrome.html`, `Build-Needed-Tools.command` |
| 43 | **Connect to Codex**: adds `[mcp_servers.needed-tools]` to `~/.codex/config.toml` (backup kept); "Copy its settings" for other MCP apps | `Sources/ClaudeLink.swift`, `Sources/Shell.swift`, `home.html` |

Files most likely to clash with your work: `Resources/shell/design.html`, `home.html`, `chrome.html`, `Sources/Shell.swift`, `Sources/Licence.swift`, and the six `Resources/tools/*/index.html`. Take extra care in those.

## Please keep (short list — the full one is in HANDOFF-FOR-CODEX.md)

- Plain, friendly wording in the UI. Never mention Keynote. No personal email addresses in the product.
- The orange lens and glass look, light and dark. Orange is `#F05A22`.
- Nothing on the phone or in the vault is deleted on its own; the MCP tools never delete.
- The sign-in page (`signin.html`) is Nathan's current job with you — keep sign-in (who they are) separate from the licence (whether they've paid). When sign-in succeeds, save the email to `UserDefaults "profile"["email"]` so the Lemon Squeezy checkout is pre-filled.
- Don't put any secret API key in the app (Lemon Squeezy, OpenAI, Anthropic).

## When unsure

If your change and the newer work conflict in a way you can't keep both, keep the newer behaviour, finish the rest, and list the conflict (file, what yours did, what's there now) at the top of your write-up so Nathan can decide.

Thank you — the owner is keeping Claude and Codex working on the same codebase, so clear notes both ways matter.
