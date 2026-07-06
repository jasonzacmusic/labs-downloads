#!/bin/bash
# Nathaniel Labs — internal downloads hub.
# Run this any time an app is rebuilt. It copies the latest .dmg for each Mac app to a
# stable name, uploads them to the GitHub Release (replacing the old ones so the download
# URL never changes), regenerates index.html, and pushes so GitHub Pages redeploys.
#
#   ./publish.sh
#
# The team always visits ONE url; the newest build is always what they get.
set -uo pipefail
cd "$(dirname "$0")"

REPO="jasonzacmusic/labs-downloads"
TAG="downloads"
MANIFEST="apps.tsv"
STAGE="assets"; mkdir -p "$STAGE"
UPDATED="$(date '+%B %-d, %Y at %-I:%M %p')"

# 1. Collect Mac installers under stable names (Shruti.dmg, Sangam.dmg, ...).
ASSETS=()
while IFS=$'\t' read -r kind name blurb src status; do
  [ "$kind" = "mac" ] || continue
  srcpath="${src/#\~/$HOME}"
  slug="$(echo "$name" | tr -d ' ')"
  if [ -f "$srcpath" ]; then
    cp "$srcpath" "$STAGE/$slug.dmg"
    ASSETS+=("$STAGE/$slug.dmg")
    echo "staged $slug.dmg  ($(du -h "$srcpath" | cut -f1))"
  else
    echo "WARN: missing $srcpath for $name (skipping its download)"
  fi
done < "$MANIFEST"

# 2. Ensure the release exists, then upload/replace assets in place.
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" --repo "$REPO" --title "Latest builds" \
        --notes "Latest internal test builds. Always current." --latest
if [ ${#ASSETS[@]} -gt 0 ]; then
  gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber
fi

# 3. Regenerate the page.
build_cards() {
  local want="$1"
  while IFS=$'\t' read -r kind name blurb src status; do
    [ "$kind" = "$want" ] || continue
    local slug badge href label size sub
    slug="$(echo "$name" | tr -d ' ')"
    if [ "$status" = "Live" ]; then badge="live"; else badge="beta"; fi
    if [ "$kind" = "mac" ]; then
      href="https://github.com/$REPO/releases/latest/download/$slug.dmg"
      label="Download"; sub="macOS · Apple Silicon"
      if [ -f "$STAGE/$slug.dmg" ]; then size=" · $(du -h "$STAGE/$slug.dmg" | cut -f1)B"; else size=""; fi
      sub="$sub$size"
    else
      href="$src"; label="Open"; sub="Web app"
    fi
    cat <<CARD
      <a class="card" href="$href"$([ "$kind" = web ] && echo ' target="_blank" rel="noopener"')>
        <div class="row">
          <span class="name">$name</span>
          <span class="badge $badge">$status</span>
        </div>
        <p class="blurb">$blurb</p>
        <div class="foot">
          <span class="sub">$sub</span>
          <span class="cta">$label &rarr;</span>
        </div>
      </a>
CARD
  done < "$MANIFEST"
}

MAC_CARDS="$(build_cards mac)"
WEB_CARDS="$(build_cards web)"

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
  body{background:var(--ink);color:var(--tx);font-family:'IBM Plex Sans',system-ui,sans-serif;-webkit-font-smoothing:antialiased;padding:48px 22px 80px}
  .wrap{max-width:920px;margin:0 auto}
  .brand{font-family:'Bricolage Grotesque',sans-serif;font-size:30px;letter-spacing:-.5px}
  .amber{color:var(--amber)}
  .tag{color:var(--mut);margin-top:6px;font-size:15px}
  .meta{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:12px;margin-top:14px}
  h2{font-family:'IBM Plex Mono',monospace;font-size:12px;font-weight:500;letter-spacing:2px;color:var(--faint);text-transform:uppercase;margin:44px 0 14px}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px}
  .card{display:flex;flex-direction:column;gap:9px;background:var(--card);border:.5px solid var(--line);border-radius:14px;padding:18px 18px 16px;text-decoration:none;color:inherit;transition:transform .12s ease,border-color .12s ease,background .12s ease}
  .card:hover{transform:translateY(-2px);border-color:var(--amber);background:var(--card2)}
  .row{display:flex;align-items:center;justify-content:space-between;gap:8px}
  .name{font-weight:600;font-size:17px}
  .badge{font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.5px;padding:3px 8px;border-radius:999px;text-transform:uppercase}
  .badge.live{color:var(--green);background:rgba(87,217,138,.12)}
  .badge.beta{color:var(--amber);background:rgba(244,166,42,.12)}
  .blurb{color:var(--mut);font-size:13.5px;line-height:1.5;flex:1}
  .foot{display:flex;align-items:center;justify-content:space-between;margin-top:4px}
  .sub{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:11px}
  .cta{color:var(--amber);font-weight:600;font-size:14px}
  .note{margin-top:40px;color:var(--faint);font-size:12.5px;line-height:1.7;border-top:.5px solid var(--line);padding-top:18px}
</style></head><body><div class="wrap">
  <div class="brand"><span class="amber">Nathaniel</span> Labs</div>
  <div class="tag">Internal downloads — always the latest build.</div>
  <div class="meta">Updated $UPDATED</div>

  <h2>Mac apps</h2>
  <div class="grid">
$MAC_CARDS
  </div>

  <h2>Web apps</h2>
  <div class="grid">
$WEB_CARDS
  </div>

  <p class="note">
    Mac apps are signed and notarized by Apple, so they open with no security warnings.
    Just download, open the .dmg, and double-click the app — it sets itself up.
    Requires an Apple Silicon Mac (M1 or newer) on a recent macOS.
    &nbsp;·&nbsp; This page is for the Nathaniel team only; please do not share the link.
  </p>
</div></body></html>
HTML

echo "index.html regenerated"

# 4. Publish (Pages redeploys on push).
git add -A
git commit -q -m "publish: refresh downloads hub ($UPDATED)" || echo "(nothing changed)"
git push -q origin main
echo ""
echo "Live at: https://jasonzacmusic.github.io/labs-downloads/"
