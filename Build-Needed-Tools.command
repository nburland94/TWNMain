#!/bin/bash
# Builds Needed Tools.app from the files beside this script.
# Needs Apple's command line tools and nothing else.

cd "$(dirname "$0")" || exit 1
say() { echo "  $*"; }
finish() { echo; read -r -p "  Press return to close." _; exit "${1:-0}"; }

echo
echo "  ─────────────────────────────────────"
echo "   Building Needed Tools"
echo "  ─────────────────────────────────────"
echo

for f in Sources/Shell.swift Info.plist Resources/shell/chrome.html Resources/icon.icns Resources/licence.json; do
  [ -e "$f" ] || { say "Missing $f — keep this script in its folder."; finish 1; }
done

if ! xcrun --find swiftc >/dev/null 2>&1; then
  say "Apple's command line tools aren't installed."
  say "A window will open to install them. Let it finish, then run this again."
  xcode-select --install >/dev/null 2>&1
  finish 1
fi

# The compiler needs to be told where the macOS SDK lives. Calling it
# through xcrun with the SDK passed explicitly is what makes that work.
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  say "The command line tools are installed but the macOS SDK is missing."
  say "That usually means they're out of date after a macOS update."
  say ""
  say "Fix: open System Settings → General → Software Update and install"
  say "any Command Line Tools update listed there, then run this again."
  say ""
  say "If none is listed, paste this into Terminal, then run this again:"
  say "    sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
  finish 1
fi

say "Tools:  $(xcode-select -p 2>/dev/null)"
say "SDK:    $(basename "$SDK")"
say "Swift:  $(xcrun --sdk macosx swiftc --version 2>/dev/null | head -1)"
echo

build() {   # $1 = target triple, $2 = output
  xcrun --sdk macosx swiftc -sdk "$SDK" -O -target "$1" -o "$2" Sources/*.swift
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say "Compiling for Apple Silicon…"
build arm64-apple-macos11.3 "$WORK/nt-arm64" 2>"$WORK/arm.log" \
  || { cp "$WORK/arm.log" "build-errors.txt"
       say "Compile failed:"; { grep -E "error:" -A 2 "$WORK/arm.log" || cat "$WORK/arm.log"; } | sed 's/^/    /' | head -30
       echo; say "The full list is saved beside this script as build-errors.txt — drop it into the chat."
       echo; say "Send those lines back and I'll fix it."; finish 1; }

say "Compiling for Intel…"
if build x86_64-apple-macos11.3 "$WORK/nt-x64" 2>"$WORK/x64.log"; then
  lipo -create -output "$WORK/Needed Tools" "$WORK/nt-arm64" "$WORK/nt-x64"
  say "Universal binary: Apple Silicon + Intel."
else
  cp "$WORK/nt-arm64" "$WORK/Needed Tools"
  say "Intel build failed — shipping Apple Silicon only."
fi

APP="Needed Tools.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$WORK/Needed Tools" "$APP/Contents/MacOS/Needed Tools"
chmod +x "$APP/Contents/MacOS/Needed Tools"
cp -R Resources/. "$APP/Contents/Resources/"

MODE="$(/usr/bin/plutil -extract provider raw -o - Resources/licence.json 2>/dev/null || echo unknown)"
if [ "$MODE" = "off" ]; then
  echo
  say "NOTE: built with NO LICENCE — it opens for anyone."
  say "Fine for your own use. Don't share this build."
  echo
fi
if [ "$MODE" = "test" ]; then
  echo
  say "NOTE: built in TEST MODE. Anyone can unlock it with the test key."
  say "Fine for trying it. Do not sell or share this build."
  echo
fi

# Ad-hoc signature. Free and local — Apple Silicon won't run unsigned code at all.
# Sort's ffprobe: clear the download quarantine and sign it, or macOS won't run it.
xattr -cr "$APP" 2>/dev/null || true
for tool in "$APP/Contents/Resources/bin/"ffprobe-*; do
  [ -f "$tool" ] && chmod +x "$tool" && codesign --force --sign - "$tool" >/dev/null 2>&1
done
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
  && say "Signed (ad-hoc)." || say "Signing failed — the app may not open on Apple Silicon."

rm -f build-errors.txt "Needed Tools.zip"
ditto -c -k --keepParent "$APP" "Needed Tools.zip"
say "Zipped for the site: Needed Tools.zip"

echo
say "Done. Opening it now."
open "$APP"
open -R "Needed Tools.zip"
finish 0
