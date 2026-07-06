#!/bin/bash
# Nathaniel Labs — push local native installers, then regenerate + deploy the hub.
# Run this on the Mac that BUILT a native app (the cloud can't build/notarize Mac apps).
# For web apps you never need to run this — the scheduled GitHub Action refreshes their
# "last updated" dates automatically. This just uploads Mac/Windows installers and refreshes.
#
#   ./publish.sh
set -uo pipefail
cd "$(dirname "$0")"
REPO="jasonzacmusic/labs-downloads"; TAG="downloads"; STAGE="assets"
rm -rf "$STAGE"; mkdir -p "$STAGE"

# Local notarized installers to host, keyed to the asset names catalog.json expects.
# Format: "SOURCE_PATH|ASSET_NAME". ghrel:owner/repo:asset pulls from another repo's release.
LOCALS=(
  "file:~/Documents/Claude/sangam/dist/Shruti-signed.dmg|Shruti-mac.dmg"
  "ghrel:jasonzacmusic/sangam:Sangam-1.0.0.dmg|Sangam-mac.dmg"
  "file:~/Desktop/Chorale-0.4.0.dmg|Chorale-mac.dmg"
  "file:~/Documents/Claude/grabit/site/downloads/GrabIt-1.8.dmg|GrabIt-mac.dmg"
  "ghrel:jasonzacmusic/MidiVisualizer-Releases:MIDI-Piano-Visualizer.dmg|MIDI-Piano-Visualizer-mac.dmg"
  "ghrel:jasonzacmusic/MidiVisualizer-Releases:MIDI-Piano-Visualizer-Setup.exe|MIDI-Piano-Visualizer-win.exe"
)

gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" --repo "$REPO" --title "Latest builds" --notes "Latest internal builds." --latest

ASSETS=()
for row in "${LOCALS[@]}"; do
  src="${row%%|*}"; name="${row##*|}"
  case "$src" in
    file:*) p="${src#file:}"; p="${p/#\~/$HOME}"
      [ -f "$p" ] || { echo "WARN  missing $p"; continue; }
      xcrun stapler validate "$p" >/dev/null 2>&1 || { echo "SKIP  $name not notarized yet"; continue; }
      cp "$p" "$STAGE/$name"; ASSETS+=("$STAGE/$name"); echo "local $name ($(du -h "$p"|cut -f1))" ;;
    ghrel:*) spec="${src#ghrel:}"; orepo="${spec%%:*}"; asset="${spec##*:}"
      if gh release download --repo "$orepo" --pattern "$asset" -O "$STAGE/$name" --clobber 2>/dev/null; then
        ASSETS+=("$STAGE/$name"); echo "ghrel $name <- $orepo"
      else echo "WARN  could not fetch $asset from $orepo"; fi ;;
  esac
done
[ ${#ASSETS[@]} -gt 0 ] && gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber

python3 gen.py
git add -A
git commit -q -m "publish: native installers + refresh ($(date '+%Y-%m-%d %H:%M'))" || echo "(nothing changed)"
git push -q origin main
echo ""
echo "Live at: https://jasonzacmusic.github.io/labs-downloads/"
