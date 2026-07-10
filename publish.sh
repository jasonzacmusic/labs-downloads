#!/bin/bash
# Nathaniel Labs — push local native installers, then regenerate + deploy the hub.
# Run this on the Mac that BUILT a native app (the cloud can't build/notarize Mac apps).
# For web apps you never need to run this — the scheduled GitHub Action refreshes their
# "last updated" dates automatically. This just uploads Mac/Windows installers and refreshes.
#
#   ./publish.sh
set -euo pipefail
cd "$(dirname "$0")"
REPO="jasonzacmusic/labs-downloads"; TAG="downloads"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/labs-downloads.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# Start from the current branch state so a scheduled refresh cannot make a successful
# asset upload look like a failed site release later in this script.
git pull --rebase --autostash origin main

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

# Keep exactly one Shruti installer on the hub release. Older publishers used versioned
# names and a release-hosted appcast; the current stable installer is Shruti-mac.dmg and
# the signed feed lives on GitHub Pages.
while IFS= read -r stale; do
  [ -n "$stale" ] || continue
  case "$stale" in
    Shruti-mac.dmg) ;;
    Shruti*.dmg|Shruti-appcast.xml)
      gh release delete-asset "$TAG" "$stale" --repo "$REPO" --yes
      echo "removed stale $stale"
      ;;
  esac
done < <(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')

# This is Shruti's backup feed; the primary GrabIt-style feed lives on Shruti's dedicated
# site. Never publish an unsigned scaffold: Shruti requires both archive and feed signing.
SHRUTI_APPCAST="$HOME/Documents/Claude/sangam/appcasts/shruti.xml"
if [ -f "$SHRUTI_APPCAST" ] \
    && grep -q 'sparkle:edSignature=' "$SHRUTI_APPCAST" \
    && grep -q 'sparkle-signatures:' "$SHRUTI_APPCAST"; then
  mkdir -p appcasts
  cp "$SHRUTI_APPCAST" appcasts/shruti.xml
  echo "local appcasts/shruti.xml (Ed25519 signed)"
else
  echo "ERROR signed Shruti appcast not ready; run sangam/scripts/generate-shruti-appcast.sh" >&2
  exit 1
fi

python3 gen.py
git add -A
git commit -q -m "publish: native installers + refresh ($(date '+%Y-%m-%d %H:%M'))" || echo "(nothing changed)"
published=false
for attempt in 1 2 3; do
  if git push -q origin main; then
    published=true
    break
  fi
  echo "push raced another refresh; rebasing (attempt $attempt/3)…"
  git pull --rebase origin main
done
[ "$published" = true ] || { echo "ERROR hub publish did not reach origin/main" >&2; exit 1; }

curl -fsSIL --retry 4 \
  "https://github.com/jasonzacmusic/labs-downloads/releases/latest/download/Shruti-mac.dmg" >/dev/null
curl -fsSIL --retry 4 \
  "https://raw.githubusercontent.com/jasonzacmusic/labs-downloads/main/appcasts/shruti.xml" >/dev/null

# The catalog resolves current version/download metadata from the release and appcast.
# Refresh it immediately rather than waiting for the six-hour safety schedule.
gh api repos/jasonzacmusic/nathaniel-labs-site/dispatches --method POST \
  -H "Accept: application/vnd.github+json" -f event_type=release-published
echo ""
echo "Live at: https://jasonzacmusic.github.io/labs-downloads/"
