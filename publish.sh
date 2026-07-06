#!/bin/bash
# Nathaniel Labs — internal downloads hub.
# Run this any time an app is rebuilt on ANY machine. It gathers the latest installer for
# each app, uploads them under stable URLs, stamps build metadata (which machine published,
# each app's latest commit), regenerates index.html, and pushes so GitHub Pages redeploys.
#
#   ./publish.sh
#
# Sources per app (apps.tsv column 4):
#   file:PATH             a local build on THIS machine (must be Apple-notarized)
#   ghrel:owner/repo:NAME pulled straight from that repo's own GitHub release (any builder)
#   url:HTTPS             a live web app (just linked)
#   soon                  not yet distributable (e.g. an iOS build heading to TestFlight)
#
# Written for macOS's stock bash 3.2 (no associative arrays).
set -uo pipefail
cd "$(dirname "$0")"

REPO="jasonzacmusic/labs-downloads"
TAG="downloads"
MANIFEST="apps.tsv"
STAGE="assets"; rm -rf "$STAGE"; mkdir -p "$STAGE"
UPDATED="$(date '+%B %-d, %Y at %-I:%M %p')"
HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"

slug_of() { echo "$1-$2" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-'; }
staged_asset() { ls "$STAGE/$1".* 2>/dev/null | head -1 | xargs -I{} basename {} 2>/dev/null; }
plat_label() { case "$1" in mac) echo "macOS";; win) echo "Windows";; linux) echo "Linux";; ipad) echo "iPadOS";; ios) echo "iOS";; web) echo "Web";; *) echo "$1";; esac; }

commit_of() {
  local r="$1"; [ "$r" = "-" ] && return
  gh api "repos/$r/commits/HEAD" 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin); c=d['commit']
    print(f\"{d['sha'][:7]} · {c['author']['date'][:10]} · {c['message'].splitlines()[0][:52]}\")
except: pass" 2>/dev/null
}

# 1. Ensure the release exists, then collect + upload installers.
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" --repo "$REPO" --title "Latest builds" --notes "Latest internal builds." --latest

ASSETS=()
while IFS=$'\t' read -r platform name blurb source status repo; do
  [ -n "${platform:-}" ] || continue
  slug="$(slug_of "$name" "$platform")"
  case "$source" in
    file:*)
      p="${source#file:}"; p="${p/#\~/$HOME}"
      [ -f "$p" ] || { echo "WARN  missing $p ($name)"; continue; }
      xcrun stapler validate "$p" >/dev/null 2>&1 || { echo "SKIP  $name not notarized yet"; continue; }
      cp "$p" "$STAGE/$slug.${p##*.}"; ASSETS+=("$STAGE/$slug.${p##*.}")
      echo "local $slug.${p##*.} ($(du -h "$p" | cut -f1))" ;;
    ghrel:*)
      spec="${source#ghrel:}"; orepo="${spec%%:*}"; asset="${spec##*:}"
      if gh release download --repo "$orepo" --pattern "$asset" -O "$STAGE/$slug.${asset##*.}" --clobber 2>/dev/null; then
        ASSETS+=("$STAGE/$slug.${asset##*.}"); echo "ghrel $slug.${asset##*.} <- $orepo"
      else echo "WARN  could not fetch $asset from $orepo ($name)"; fi ;;
    *) : ;;
  esac
done < "$MANIFEST"

[ ${#ASSETS[@]} -gt 0 ] && gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber

# 2. Build the page cards.
build_section() {   # $1 = native | web
  local group="$1"
  while IFS=$'\t' read -r platform name blurb source status repo; do
    [ -n "${platform:-}" ] || continue
    [ "$group" = web ] && [ "$platform" != web ] && continue
    [ "$group" = native ] && [ "$platform" = web ] && continue
    local slug badge href label sub meta asset
    slug="$(slug_of "$name" "$platform")"
    case "$status" in Live) badge=live;; Building|Soon) badge=soon;; *) badge=beta;; esac
    meta="$(commit_of "$repo")"
    href=""; label=""
    if [ "$platform" = web ]; then
      href="${source#url:}"; label="Open"; sub="Web app"
    else
      asset="$(staged_asset "$slug")"
      if [ -n "$asset" ]; then
        href="https://github.com/$REPO/releases/latest/download/$asset"
        label="Download"; sub="$(plat_label "$platform")"; [ "$platform" = mac ] && sub="$sub · notarized"
      elif [ "$source" = soon ]; then
        sub="$(plat_label "$platform") · coming to TestFlight"
      else continue; fi
    fi
    if [ -n "$href" ]; then
      local ex=""; [ "$platform" = web ] && ex=' target="_blank" rel="noopener"'
      echo "      <a class=\"card\" href=\"$href\"$ex>"
    else
      echo "      <div class=\"card dim\">"
    fi
    echo "        <div class=\"row\"><span class=\"name\">$name</span><span class=\"badge $badge\">$status</span></div>"
    echo "        <p class=\"blurb\">$blurb</p>"
    [ -n "$meta" ] && echo "        <p class=\"commit\">$meta</p>"
    echo "        <div class=\"foot\"><span class=\"sub\">$sub</span>$([ -n "$label" ] && echo "<span class=\"cta\">$label &rarr;</span>")</div>"
    [ -n "$href" ] && echo "      </a>" || echo "      </div>"
  done < "$MANIFEST"
}

NATIVE_CARDS="$(build_section native)"
WEB_CARDS="$(build_section web)"

cat > index.html <<HTML
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Nathaniel Labs — Internal Downloads</title>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@700&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root{--ink:#0B0C10;--card:#14161C;--card2:#1B1E26;--line:#262A33;--tx:#F4F3EE;--mut:#A0A4AE;--faint:#6A6E78;--amber:#F4A62A;--green:#57D98A}
  *{box-sizing:border-box;margin:0}
  body{background:var(--ink);color:var(--tx);font-family:'IBM Plex Sans',system-ui,sans-serif;-webkit-font-smoothing:antialiased;padding:46px 22px 80px}
  .wrap{max-width:940px;margin:0 auto}
  .brand{font-family:'Bricolage Grotesque',sans-serif;font-size:30px;letter-spacing:-.5px}
  .amber{color:var(--amber)}
  .tag{color:var(--mut);margin-top:6px;font-size:15px}
  .meta{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:12px;margin-top:12px;line-height:1.6}
  h2{font-family:'IBM Plex Mono',monospace;font-size:12px;font-weight:500;letter-spacing:2px;color:var(--faint);text-transform:uppercase;margin:42px 0 14px}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(266px,1fr));gap:14px}
  .card{display:flex;flex-direction:column;gap:8px;background:var(--card);border:.5px solid var(--line);border-radius:14px;padding:18px;text-decoration:none;color:inherit;transition:transform .12s,border-color .12s,background .12s}
  a.card:hover{transform:translateY(-2px);border-color:var(--amber);background:var(--card2)}
  .card.dim{opacity:.6}
  .row{display:flex;align-items:center;justify-content:space-between;gap:8px}
  .name{font-weight:600;font-size:17px}
  .badge{font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.5px;padding:3px 8px;border-radius:999px;text-transform:uppercase}
  .badge.live{color:var(--green);background:rgba(87,217,138,.12)}
  .badge.beta{color:var(--amber);background:rgba(244,166,42,.12)}
  .badge.soon{color:var(--faint);background:rgba(160,164,174,.1)}
  .blurb{color:var(--mut);font-size:13.5px;line-height:1.5;flex:1}
  .commit{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:10.5px;line-height:1.4}
  .foot{display:flex;align-items:center;justify-content:space-between;margin-top:4px}
  .sub{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:11px}
  .cta{color:var(--amber);font-weight:600;font-size:14px}
  .note{margin-top:40px;color:var(--faint);font-size:12.5px;line-height:1.7;border-top:.5px solid var(--line);padding-top:18px}
</style></head><body><div class="wrap">
  <div class="brand"><span class="amber">Nathaniel</span> Labs</div>
  <div class="tag">Internal downloads — always the latest build.</div>
  <div class="meta">Updated $UPDATED &nbsp;·&nbsp; published from &ldquo;$HOST&rdquo;</div>

  <h2>Apps</h2>
  <div class="grid">
$NATIVE_CARDS
  </div>

  <h2>Web apps</h2>
  <div class="grid">
$WEB_CARDS
  </div>

  <p class="note">
    macOS apps are Apple-notarized, so they open with no warnings — download, open the .dmg,
    double-click, and the app sets itself up. Requires an Apple Silicon Mac (M1 or newer).
    Each card shows that app's latest code change (commit, date). iPad/iOS apps arrive via
    TestFlight when ready. &nbsp;·&nbsp; Team only; please don't share the link.
  </p>
</div></body></html>
HTML
echo "index.html regenerated"

gh release edit "$TAG" --repo "$REPO" \
  --notes "Latest internal builds. Published from \"$HOST\" on $UPDATED." >/dev/null 2>&1 || true
git add -A
git commit -q -m "publish: refresh hub from \"$HOST\" ($UPDATED)" || echo "(nothing changed)"
git push -q origin main
echo ""
echo "Live at: https://jasonzacmusic.github.io/labs-downloads/"
