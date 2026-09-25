#!/bin/bash
# Needed Vault for iPhone — makes the Xcode project and opens it.
# Double-click this. The first time it fetches XcodeGen (a small free tool) into this folder.
cd "$(dirname "$0")" || exit 1
say() { printf '\n  %s\n' "$1"; }

if ! xcode-select -p >/dev/null 2>&1 || [ ! -d "$(xcode-select -p)/Platforms/iPhoneOS.platform" ]; then
  say "Xcode isn't installed (or isn't the active developer tools)."
  say "Install Xcode from the App Store, open it once, then double-click this again."
  read -r -p "  Press Return to close. " _; exit 1
fi

GEN=""
if command -v xcodegen >/dev/null 2>&1; then GEN="xcodegen"
elif [ -x "./.tools/xcodegen/bin/xcodegen" ]; then GEN="./.tools/xcodegen/bin/xcodegen"
else
  say "Fetching XcodeGen…"
  mkdir -p .tools && curl -fsSL -o .tools/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip \
    && (cd .tools && unzip -oq xcodegen.zip) && GEN="./.tools/xcodegen/bin/xcodegen"
  [ -z "$GEN" ] && { say "Couldn't fetch XcodeGen. With Homebrew: brew install xcodegen — then run this again."; read -r -p "  Press Return to close. " _; exit 1; }
fi

TEAM=""
[ -f .team ] && TEAM="$(cat .team)"
if [ -z "$TEAM" ]; then
  say "Your Apple Team ID — Xcode › Settings › Accounts › your team (10 letters and numbers)."
  say "Or just press Return and pick your team in Xcode (Signing & Capabilities, for both targets)."
  read -r -p "  Team ID: " TEAM
  [ -n "$TEAM" ] && echo "$TEAM" > .team
fi
export NV_TEAM="$TEAM"

"$GEN" generate --quiet || { say "XcodeGen stopped — send me what it printed."; read -r -p "  Press Return to close. " _; exit 1; }
say "Opening Xcode. Plug in your iPhone (or pick it at the top), then press ▶."
open NeededVault.xcodeproj
