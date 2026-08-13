#!/bin/bash
# Nathaniel Labs — push local native installers, then regenerate + deploy the hub.
# Run this on the Mac that BUILT a native app (the cloud can't build/notarize Mac apps).
# For web apps you never need to run this. Native releases upload their notarized installers
# and regenerate the catalog here; the Labs site refresh is release-driven, not polled.
#
#   ./publish.sh
set -euo pipefail
cd "$(dirname "$0")"
export GIT_TERMINAL_PROMPT=0   # never hang on an interactive credential ask
REPO="jasonzacmusic/labs-downloads"; TAG="downloads"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/labs-downloads.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# Start from the current branch state so a scheduled refresh cannot make a successful
# asset upload look like a failed site release later in this script.
git pull --rebase --autostash origin main

# Local notarized installers to host, keyed to the asset names catalog.json expects.
# Format: "SOURCE_PATH|ASSET_NAME". ghrel:owner/repo:asset pulls from another repo's
# LATEST release; ghrel:owner/repo@tag:asset pins an explicit release tag (required on
# shared repos like sangam, where "latest" can belong to a different product).
# SHRUTI_DMG lets the caller (release-shruti.sh, possibly running from a git worktree)
# point at the exact notarized DMG it just built, instead of the canonical checkout's
# dist/ — which may be stale or belong to a different release. Falls back to canonical.
SHRUTI_DMG_SRC="${SHRUTI_DMG:-$HOME/Documents/New project/shruti/dist/Shruti-signed.dmg}"
# The only Net Sense checkout on this Mac is under "Claude Code"; the old
# "Claude" path no longer exists, and a missing file here is merely WARNed and
# skipped further down — so the wrong default would quietly leave Net Sense on
# an old build while the publish still reported success.
NET_SENSE_DMG_SRC="${NET_SENSE_DMG:-$HOME/Documents/Claude Code/net-sense/mac/build/Net-Sense-mac.dmg}"
GRABIT_REPO_SRC="${GRABIT_REPO:-$HOME/Documents/Claude Code/grabit}"
GRABIT_VERSION="$(plutil -extract CFBundleShortVersionString raw "$GRABIT_REPO_SRC/Resources/Info.plist" 2>/dev/null || true)"
GRABIT_BUILD="$(plutil -extract CFBundleVersion raw "$GRABIT_REPO_SRC/Resources/Info.plist" 2>/dev/null || true)"
GRABIT_DMG_SRC="${GRABIT_DMG:-$GRABIT_REPO_SRC/build/GrabIt-$GRABIT_VERSION.dmg}"
# MIDI Visualizer candidates are built and notarized locally for internal
# testing. Accept that exact DMG when supplied; the GitHub-release fallback is
# retained for the normal scheduled hub refresh and is never used by this path.
MIDI_VISUALIZER_DMG_SRC="${MIDI_VISUALIZER_DMG:-}"
MIDI_VISUALIZER_DMG_ENTRY="ghrel:jasonzacmusic/MidiVisualizer-Releases:MIDI-Piano-Visualizer.dmg"
if [ -n "$MIDI_VISUALIZER_DMG_SRC" ]; then
  MIDI_VISUALIZER_DMG_ENTRY="file:${MIDI_VISUALIZER_DMG_SRC}"
fi
# Chorale: always ship the NEWEST notarized DMG on the Desktop (the notarize
# script writes ~/Desktop/Chorale-<version>.dmg on every release).
CHORALE_DMG_SRC="$(ls -t "$HOME"/Desktop/Chorale-*.dmg 2>/dev/null | head -1 || true)"
NET_SENSE_ROW="file:${NET_SENSE_DMG_SRC}|Net-Sense-mac.dmg"
SHRUTI_ROW="file:${SHRUTI_DMG_SRC}|Shruti-mac.dmg"
GRABIT_ROW="file:${GRABIT_DMG_SRC}|GrabIt-mac.dmg"
NSM_FLOW_DIST="${NSM_FLOW_DIST:-$HOME/Documents/Claude/nsm-flow-clone/dist-release}"
NSM_FLOW_ROWS=(
  "file:${NSM_FLOW_DIST}/NSM-Flow-mac-Apple-Silicon.dmg|NSM-Flow-mac-Apple-Silicon.dmg"
  "file:${NSM_FLOW_DIST}/NSM-Flow-mac-Intel.dmg|NSM-Flow-mac-Intel.dmg"
  "file:${NSM_FLOW_DIST}/NSM-Flow-windows-x64-setup.exe|NSM-Flow-windows-x64-setup.exe"
  "file:${NSM_FLOW_DIST}/NSM-Flow-windows-x64.msi|NSM-Flow-windows-x64.msi"
)
LOCALS=(
  "$NET_SENSE_ROW"
  "$SHRUTI_ROW"
  "ghrel:jasonzacmusic/sangam@v1.1.0-rc.7:Sangam-1.1.0-rc.7.dmg|Sangam-mac.dmg"
  "file:${CHORALE_DMG_SRC}|Chorale-mac.dmg"
  "$GRABIT_ROW"
  "${MIDI_VISUALIZER_DMG_ENTRY}|MIDI-Piano-Visualizer-mac.dmg"
  "ghrel:jasonzacmusic/MidiVisualizer-Releases:MIDI-Piano-Visualizer-Setup.exe|MIDI-Piano-Visualizer-win.exe"
  # NSM Photos (internal team app). Built + shipped by nathaniel-photo-hub's own
  # macapp-native/ship.sh, which uploads straight to this release; this row is just
  # a refresh path when a freshly built DMG is sitting locally.
  # No secrets baked in — safe on the public downloads release.
  "file:$HOME/Documents/Claude/nathaniel-photo-hub/macapp-native/build/NSMPhotos-mac.dmg|NSMPhotos-mac.dmg"
  # NSM Flow. The two Mac DMGs are signed + notarized by nsm-flow's own
  # scripts/release-macos.sh, which writes them to dist-release/. The Windows
  # pair comes out of the nsm-flow GitHub Actions matrix and is staged into the
  # same folder — Windows installers are unsigned until Nathaniel has a code
  # signing certificate, so they carry no staple and skip the notarize gate.
  "${NSM_FLOW_ROWS[@]}"
)
if [ "${NET_SENSE_ONLY:-0}" = "1" ]; then
  LOCALS=("$NET_SENSE_ROW")
elif [ "${SHRUTI_ONLY:-0}" = "1" ]; then
  LOCALS=("$SHRUTI_ROW")
elif [ "${GRABIT_ONLY:-0}" = "1" ]; then
  LOCALS=("$GRABIT_ROW")
elif [ "${NSM_FLOW_ONLY:-0}" = "1" ]; then
  LOCALS=("${NSM_FLOW_ROWS[@]}")
fi

gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" --repo "$REPO" --title "Latest builds" --notes "Latest internal builds." --latest

ASSETS=()
for row in "${LOCALS[@]}"; do
  src="${row%%|*}"; name="${row##*|}"
  case "$src" in
    file:*) p="${src#file:}"; p="${p/#\~/$HOME}"
      [ -f "$p" ] || { echo "WARN  missing $p"; continue; }
      # Stapling is an Apple concept: only .dmg/.pkg/.zip carry a notarization
      # ticket. Gating a Windows .exe/.msi on it would silently skip every
      # Windows upload, so the gate applies to Mac artifacts only.
      case "$name" in
        *.dmg|*.pkg)
          xcrun stapler validate "$p" >/dev/null 2>&1 \
            || { echo "SKIP  $name not notarized yet"; continue; } ;;
      esac
      cp "$p" "$STAGE/$name"; ASSETS+=("$STAGE/$name"); echo "local $name ($(du -h "$p"|cut -f1))" ;;
    ghrel:*) spec="${src#ghrel:}"; orepo="${spec%%:*}"; asset="${spec##*:}"
      rtag=""
      case "$orepo" in *@*) rtag="${orepo##*@}"; orepo="${orepo%%@*}" ;; esac
      if gh release download ${rtag:+"$rtag"} --repo "$orepo" --pattern "$asset" -O "$STAGE/$name" --clobber 2>/dev/null; then
        ASSETS+=("$STAGE/$name"); echo "ghrel $name <- $orepo${rtag:+@$rtag}"
      else echo "WARN  could not fetch $asset from $orepo${rtag:+@$rtag}"; fi ;;
  esac
done
if { [ "${NET_SENSE_ONLY:-0}" = "1" ] || [ "${SHRUTI_ONLY:-0}" = "1" ] \
     || [ "${GRABIT_ONLY:-0}" = "1" ] \
     || [ "${NSM_FLOW_ONLY:-0}" = "1" ]; } \
    && [ ${#ASSETS[@]} -eq 0 ]; then
  # A product-specific release that could not stage its installer must fail loudly:
  # otherwise the appcast advances while the hub keeps serving the previous DMG.
  echo "ERROR requested installer missing or not notarized; nothing uploaded" >&2
  exit 1
fi
if [ "${GRABIT_ONLY:-0}" = "1" ] && [ -f "$STAGE/GrabIt-mac.dmg" ]; then
  GRABIT_SHA="$(shasum -a 256 "$STAGE/GrabIt-mac.dmg" | awk '{print $1}')"
  GRABIT_SIZE="$(stat -f %z "$STAGE/GrabIt-mac.dmg")"
  cat > "$STAGE/grabit.json" <<JSON
{
  "app": "grabit",
  "version": "$GRABIT_VERSION",
  "build": "$GRABIT_BUILD",
  "notes": "Screenshot permission restart and resume reliability",
  "date": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "sha256": "$GRABIT_SHA",
  "size": $GRABIT_SIZE,
  "url": "https://github.com/jasonzacmusic/labs-downloads/releases/download/downloads/GrabIt-mac.dmg"
}
JSON
  ASSETS+=("$STAGE/grabit.json")
fi
if [ ${#ASSETS[@]} -gt 0 ]; then
  gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber
fi

# Keep exactly one installer per app on the hub release. Older publishers used versioned
# names and a release-hosted appcast; the current stable names are unversioned and the
# signed Shruti feed lives on GitHub Pages.
while IFS= read -r stale; do
  [ -n "$stale" ] || continue
  case "$stale" in
    Shruti-mac.dmg) ;;
    Shruti*.dmg|Shruti-appcast.xml)
      gh release delete-asset "$TAG" "$stale" --repo "$REPO" --yes
      echo "removed stale $stale"
      ;;
    MIDI-Piano-Visualizer-mac.dmg) ;;
    MIDI-Piano-Visualizer*.dmg)
      gh release delete-asset "$TAG" "$stale" --repo "$REPO" --yes
      echo "removed stale $stale"
      ;;
  esac
done < <(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')

# This is Shruti's backup feed; the primary GrabIt-style feed lives on Shruti's dedicated
# site. Never publish an unsigned scaffold: Shruti requires both archive and feed signing.
if [ "${NET_SENSE_ONLY:-0}" != "1" ] && [ "${NSM_FLOW_ONLY:-0}" != "1" ] \
    && [ "${GRABIT_ONLY:-0}" != "1" ]; then
  SHRUTI_APPCAST="${SHRUTI_APPCAST_SRC:-$HOME/Documents/New project/shruti/appcasts/shruti.xml}"
  if [ -f "$SHRUTI_APPCAST" ] \
      && grep -q 'sparkle:edSignature=' "$SHRUTI_APPCAST" \
      && grep -q 'sparkle-signatures:' "$SHRUTI_APPCAST"; then
    mkdir -p appcasts
    cp "$SHRUTI_APPCAST" appcasts/shruti.xml
    echo "local appcasts/shruti.xml (Ed25519 signed)"
  else
    echo "ERROR signed Shruti appcast not ready; run shruti/scripts/generate-shruti-appcast.sh" >&2
    exit 1
  fi
fi

if [ "${SHRUTI_ONLY:-0}" = "1" ]; then
  # A Shruti release changes the appcast and the source repo's update timestamp. Always
  # regenerate the page in the same release so the umbrella cannot stay one version behind.
  HUB_CURATED_ONLY=1 HUB_REFRESH_REPO=jasonzacmusic/shruti python3 gen.py
  # gen.py updates both the rendered page and its source-state snapshot. Committing only
  # index.html leaves the checkout dirty and makes the next targeted refresh compare
  # against stale release metadata.
  git add appcasts/shruti.xml index.html state.json
elif [ "${GRABIT_ONLY:-0}" = "1" ]; then
  HUB_CURATED_ONLY=1 HUB_REFRESH_REPO=jasonzacmusic/grabit python3 gen.py
  git add index.html state.json
else
  python3 gen.py
  git add -A
fi
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

# The catalog resolves current version/download metadata from the release and appcast.
# Refresh it immediately as the release event. This runs
# BEFORE the edge-availability checks below: the asset upload and git push already
# succeeded (both verified above), so the catalog must refresh even if GitHub's download
# CDN is briefly lagging.
gh api repos/jasonzacmusic/nathaniel-labs-site/dispatches --method POST \
  -H "Accept: application/vnd.github+json" -f event_type=release-published || \
  echo "WARN catalog dispatch failed; run the Labs site refresh locally before closing the release"

# Best-effort edge check: GitHub's release-download CDN can lag 10-30 s after a --clobber,
# so give it real time but never fail the publish over propagation (the bytes are up).
curl -fsSIL --retry 8 --retry-all-errors --retry-delay 5 \
  "https://github.com/jasonzacmusic/labs-downloads/releases/latest/download/Shruti-mac.dmg" >/dev/null \
  || echo "WARN Shruti-mac.dmg not yet visible on the download CDN (propagation lag)"
curl -fsSIL --retry 8 --retry-all-errors --retry-delay 5 \
  "https://raw.githubusercontent.com/jasonzacmusic/labs-downloads/main/appcasts/shruti.xml" >/dev/null \
  || echo "WARN appcast raw URL not yet visible (propagation lag)"
if [ "${NET_SENSE_ONLY:-0}" = "1" ]; then
  curl -fsSIL --retry 8 --retry-all-errors --retry-delay 5 \
    "https://github.com/jasonzacmusic/labs-downloads/releases/latest/download/Net-Sense-mac.dmg" >/dev/null \
    || echo "WARN Net-Sense-mac.dmg not yet visible on the download CDN (propagation lag)"
fi
if [ "${GRABIT_ONLY:-0}" = "1" ]; then
  curl -fsSIL --retry 8 --retry-all-errors --retry-delay 5 \
    "https://github.com/jasonzacmusic/labs-downloads/releases/download/downloads/GrabIt-mac.dmg" >/dev/null \
    || echo "WARN GrabIt-mac.dmg not yet visible on the download CDN (propagation lag)"
fi
echo ""
echo "Live at: https://jasonzacmusic.github.io/labs-downloads/"
