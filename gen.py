#!/usr/bin/env python3
"""Generate the Nathaniel Labs internal apps hub.

- Auto-discovers every app in the GitHub org (any repo that is a native/iOS app, i.e. has a
  .dmg/.exe release or a Capacitor/ios project), so new apps appear on their own.
- Auto-detects platform per repo from GitHub itself: iOS (capacitor.config/ios dir), macOS
  or Windows (release installers), Web (a live site). No hand-maintained platform flags.
- Orders by latest GitHub activity; groups into Mac / iOS / Web with category emojis.
- catalog.json supplies pretty names, public URLs, categories, App Store / sales links.
- state.json caches dates + detected platform so a token-less cloud run degrades gracefully.

Uses the `gh` CLI (present locally and on GitHub runners) for all GitHub calls.
"""
import json, os, subprocess, datetime, html, re

ORG = "jasonzacmusic"
REPO = f"{ORG}/labs-downloads"
TAG = "downloads"
HERE = os.path.dirname(os.path.abspath(__file__))

CAT_EMOJI = {"Audio": "🔊", "Music": "🎵", "Practice": "🎹", "Productivity": "🛠️",
             "Portal": "🎓", "Team": "🧩", "Utility": "⚡", "Landing": "🌐", "App": "✨"}
PLAT = {"mac": "macOS", "win": "Windows", "ios": "iOS", "web": "Web"}
GH_TIMEOUT_SECONDS = int(os.environ.get("HUB_GH_TIMEOUT_SECONDS", "12"))


def gh_json(args):
    try:
        r = subprocess.run(
            ["gh"] + args,
            capture_output=True,
            text=True,
            timeout=GH_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return None
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


def api(path):
    return gh_json(["api", path])


# ---------- cache ----------
CACHE_PATH = os.path.join(HERE, "state.json")
try:
    CACHE = json.load(open(CACHE_PATH))
except Exception:
    CACHE = {}


def cput(repo, key, val):
    CACHE.setdefault(repo, {})[key] = val


def cget(repo, key, default=None):
    return CACHE.get(repo, {}).get(key, default)


# ---------- GitHub facts ----------
def hub_assets():
    d = api(f"/repos/{REPO}/releases/tags/{TAG}") or {}
    return {a["name"] for a in d.get("assets", [])}


def repo_meta(repo):
    """pushed_at + first line of latest commit; cached, degrades to cache on no-access."""
    info = api(f"/repos/{repo}")
    if info:
        cput(repo, "pushed", info.get("pushed_at") or cget(repo, "pushed", ""))
    c = api(f"/repos/{repo}/commits/HEAD")
    if c:
        try:
            cput(repo, "commit", c["commit"]["message"].splitlines()[0][:56])
        except Exception:
            pass
    return cget(repo, "pushed", ""), cget(repo, "commit", "")


def detect_ios(repo, langs):
    """True if the repo is a Capacitor/native iOS project. Cheap-gated on Swift, cached."""
    if cget(repo, "ios") is not None and not langs:
        return cget(repo, "ios")
    if "Swift" not in (langs or {}):
        cput(repo, "ios", cget(repo, "ios", False))
        return cget(repo, "ios", False)
    root = api(f"/repos/{repo}/contents") or []
    names = {e.get("name", "") for e in root} if isinstance(root, list) else set()
    is_ios = ("capacitor.config.ts" in names or "capacitor.config.js" in names or "ios" in names)
    cput(repo, "ios", is_ios)
    return is_ios


def native_from_release(repo):
    """Return {'mac': url, 'win': url} for installers on the repo's own latest release."""
    d = api(f"/repos/{repo}/releases/latest") or {}
    out = {}
    for a in d.get("assets", []):
        n = a["name"].lower()
        if n.endswith(".dmg") and "mac" not in out:
            out["mac"] = a["browser_download_url"]
        elif n.endswith(".exe") and "win" not in out:
            out["win"] = a["browser_download_url"]
    return out


def languages(repo):
    return api(f"/repos/{repo}/languages") or {}


# ---------- assemble ----------
def prettify(repo):
    n = repo.split("/")[-1]
    return re.sub(r"[-_]+", " ", n).title()


def rel_time(iso):
    if not iso:
        return ("", "")
    try:
        t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except Exception:
        return ("", "")
    secs = (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()
    if secs < 3600:
        s = f"{int(secs//60)}m ago"
    elif secs < 86400:
        s = f"{int(secs//3600)}h ago"
    elif secs < 86400 * 30:
        s = f"{int(secs//86400)}d ago"
    else:
        s = t.strftime("%b %-d, %Y")
    return (s, t.strftime("%Y-%m-%d %H:%M"))


def build():
    cat = json.load(open(os.path.join(HERE, "catalog.json")))["apps"]
    by_repo = {a["repo"]: a for a in cat if a.get("repo")}
    assets = hub_assets()
    apps = {}   # key -> record

    def add(key, name, category, repo=None):
        apps.setdefault(key, {"name": name, "category": category, "repo": repo,
                              "downloads": [], "web": None, "ios": False,
                              "ios_url": None, "site": None})
        return apps[key]

    # 1. Curated catalog apps (pretty names, public URLs, App Store / sales links).
    for a in cat:
        key = a.get("repo") or a["name"]
        rec = add(key, a["name"], a.get("category", "App"), a.get("repo"))
        rec["web"] = a.get("web") or rec["web"]
        rec["ios_url"] = a.get("ios_url") or rec["ios_url"]
        rec["site"] = a.get("site") or rec["site"]
        if a.get("ios") == "live" or a.get("ios") == "soon":
            rec["ios"] = True
        for n in a.get("native", []):
            if n["asset"] in assets:
                rec["downloads"].append((n["platform"],
                    f"https://github.com/{REPO}/releases/latest/download/{n['asset']}"))

    # 2. Auto-discover native / iOS apps anywhere in the org (future-proof).
    repos = gh_json(["repo", "list", ORG, "--limit", "200", "--no-archived",
                     "--json", "name,homepageUrl,pushedAt"]) or []
    for r in repos:
        full = f"{ORG}/{r['name']}"
        langs = languages(full)
        ios = detect_ios(full, langs)
        rel = native_from_release(full) if "Swift" in langs or "C++" in langs else {}
        if not (ios or rel):
            continue   # not a native/iOS app -> web apps stay curated via the sheet
        src = by_repo.get(full)
        key = full
        rec = add(key, src["name"] if src else prettify(full),
                  (src or {}).get("category", "App"), full)
        if src:
            rec["web"] = rec["web"] or src.get("web")
            rec["ios_url"] = rec["ios_url"] or src.get("ios_url")
            rec["site"] = rec["site"] or src.get("site")
        if not rec["web"] and r.get("homepageUrl") and "replit.com" not in r["homepageUrl"]:
            rec["web"] = r["homepageUrl"]
        if ios:
            rec["ios"] = True
        for plat, url in rel.items():
            if plat not in {p for p, _ in rec["downloads"]}:
                rec["downloads"].append((plat, url))

    # 3. Dates + commit, then classify + sort.
    out = []
    for rec in apps.values():
        pushed, commit = repo_meta(rec["repo"]) if rec["repo"] else ("", "")
        rec["pushed"], rec["commit"] = pushed, commit
        rec["rel"], rec["abs"] = rel_time(pushed)
        has_mac = any(p == "mac" for p, _ in rec["downloads"])
        has_win = any(p == "win" for p, _ in rec["downloads"])
        rec["section"] = "mac" if has_mac else "ios" if rec["ios"] else "win" if has_win else "web"
        out.append(rec)
    out.sort(key=lambda a: a["pushed"], reverse=True)
    return out


# ---------- render ----------
def card(rec):
    name = html.escape(rec["name"])
    emoji = CAT_EMOJI.get(rec["category"], "✨")
    rel, ab = rec["rel"], rec["abs"]
    updated = f'<span class="upd" title="{ab}">updated {rel}</span>' if rel else ""
    commit = f'<p class="commit">{html.escape(rec["commit"])}</p>' if rec["commit"] else ""

    chips = [(PLAT[p], p) for p, _ in rec["downloads"]]
    if rec["ios"]:
        chips.append(("iOS", "ios"))
    if rec["web"]:
        chips.append(("Web", "web"))
    seen = set(); chipline = ""
    for label, c in chips:
        if c in seen:
            continue
        seen.add(c)
        chipline += f'<span class="chip {c}">{html.escape(label)}</span>'

    acts = []
    for plat, url in rec["downloads"]:
        acts.append(f'<a class="btn" href="{html.escape(url)}">Download {PLAT[plat]} &darr;</a>')
    if rec["ios"]:
        if rec["ios_url"]:
            acts.append(f'<a class="btn ios" href="{html.escape(rec["ios_url"])}" target="_blank" rel="noopener">App Store &rarr;</a>')
        else:
            acts.append('<span class="btn softios">iOS · TestFlight soon</span>')
    if rec["web"]:
        acts.append(f'<a class="btn ghost" href="{html.escape(rec["web"])}" target="_blank" rel="noopener">Open &rarr;</a>')
    if rec["site"]:
        acts.append(f'<a class="btn ghost" href="{html.escape(rec["site"])}" target="_blank" rel="noopener">Sales page &rarr;</a>')

    iosclass = " isios" if rec["section"] == "ios" else ""
    return f"""      <div class="card{iosclass}">
        <div class="row"><span class="name">{emoji} {name}</span>{updated}</div>
        <p class="sub">{html.escape(rec['category'])}</p>
        <div class="chips">{chipline}</div>
        {commit}
        <div class="acts">{''.join(acts)}</div>
      </div>"""


def section(recs, want):
    cards = "\n".join(card(r) for r in recs if r["section"] == want)
    return cards or '      <p class="empty">Nothing here yet.</p>'


def main():
    apps = build()
    mac = [a for a in apps if a["section"] in ("mac", "win")]
    ios = [a for a in apps if a["section"] == "ios"]
    web = [a for a in apps if a["section"] == "web"]
    host = os.environ.get("HUB_HOST") or subprocess.run(
        ["bash", "-c", "scutil --get ComputerName 2>/dev/null || hostname"],
        capture_output=True, text=True).stdout.strip() or "the cloud"
    updated = datetime.datetime.now().strftime("%B %-d, %Y at %-I:%M %p")

    def cards(recs):
        return "\n".join(card(r) for r in recs) or '      <p class="empty">Nothing here yet.</p>'

    page = (TEMPLATE
            .replace("{{MAC}}", cards(mac)).replace("{{IOS}}", cards(ios)).replace("{{WEB}}", cards(web))
            .replace("{{NMAC}}", str(len(mac))).replace("{{NIOS}}", str(len(ios))).replace("{{NWEB}}", str(len(web)))
            .replace("{{UPDATED}}", updated).replace("{{HOST}}", html.escape(host)))
    open(os.path.join(HERE, "index.html"), "w").write(page)
    json.dump(CACHE, open(CACHE_PATH, "w"), indent=0, sort_keys=True)
    print(f"generated — {len(mac)} Mac, {len(ios)} iOS, {len(web)} Web")


TEMPLATE = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Nathaniel Labs — Internal Apps</title>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@700&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root{--ink:#0B0C10;--card:#14161C;--card2:#1B1E26;--line:#262A33;--tx:#F4F3EE;--mut:#A0A4AE;--faint:#6A6E78;--amber:#F4A62A;--green:#57D98A;--violet:#8F82FF;--blue:#4E9BF0}
  *{box-sizing:border-box;margin:0}
  body{background:var(--ink);color:var(--tx);font-family:'IBM Plex Sans',system-ui,sans-serif;-webkit-font-smoothing:antialiased;padding:46px 22px 80px}
  .wrap{max-width:960px;margin:0 auto}
  .brand{font-family:'Bricolage Grotesque',sans-serif;font-size:32px;letter-spacing:-.5px}
  .amber{color:var(--amber)}
  .tag{color:var(--mut);margin-top:6px;font-size:15px}
  .meta{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:12px;margin-top:12px}
  h2{display:flex;align-items:center;gap:9px;font-family:'IBM Plex Sans',sans-serif;font-size:15px;font-weight:600;color:var(--tx);margin:40px 0 14px}
  h2 .n{font-family:'IBM Plex Mono',monospace;font-size:12px;color:var(--faint);font-weight:400}
  h2 .ln{flex:1;height:.5px;background:var(--line)}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:14px}
  .card{display:flex;flex-direction:column;gap:7px;background:var(--card);border:.5px solid var(--line);border-radius:14px;padding:16px 18px}
  .card.isios{border-color:rgba(143,130,255,.42)}
  .row{display:flex;align-items:baseline;justify-content:space-between;gap:10px}
  .name{font-weight:600;font-size:16.5px}
  .upd{color:var(--green);font-family:'IBM Plex Mono',monospace;font-size:10.5px;white-space:nowrap}
  .sub{color:var(--mut);font-size:12.5px}
  .chips{display:flex;flex-wrap:wrap;gap:6px}
  .chip{font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.3px;padding:2px 8px;border-radius:999px}
  .chip.mac{color:var(--amber);background:rgba(244,166,42,.13)}
  .chip.win{color:var(--blue);background:rgba(78,155,240,.14)}
  .chip.ios{color:var(--violet);background:rgba(143,130,255,.16)}
  .chip.web{color:var(--green);background:rgba(87,217,138,.13)}
  .commit{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:10.5px;line-height:1.4}
  .acts{display:flex;flex-wrap:wrap;gap:8px;margin-top:6px}
  .btn{font-size:13px;font-weight:500;text-decoration:none;color:var(--ink);background:var(--amber);padding:6px 12px;border-radius:8px}
  .btn.ghost{color:var(--amber);background:transparent;border:.5px solid var(--line)}
  .btn.ios{color:#fff;background:var(--violet)}
  .btn.softios{color:var(--violet);background:rgba(143,130,255,.14);font-weight:400}
  a.btn:hover{opacity:.9}
  .empty{color:var(--faint);font-size:13px}
  .note{margin-top:44px;color:var(--faint);font-size:12.5px;line-height:1.7;border-top:.5px solid var(--line);padding-top:18px}
</style></head><body><div class="wrap">
  <div class="brand"><span class="amber">Nathaniel</span> Labs</div>
  <div class="tag">Every app we build — updated automatically from GitHub.</div>
  <div class="meta">Refreshed {{UPDATED}} · from {{HOST}}</div>

  <h2>🖥️ Mac apps <span class="n">{{NMAC}}</span><span class="ln"></span></h2>
  <div class="grid">
{{MAC}}
  </div>

  <h2>📱 iOS &amp; iPad apps <span class="n">{{NIOS}}</span><span class="ln"></span></h2>
  <div class="grid">
{{IOS}}
  </div>

  <h2>🌐 Web apps <span class="n">{{NWEB}}</span><span class="ln"></span></h2>
  <div class="grid">
{{WEB}}
  </div>

  <p class="note">
    Platform is detected from each repo automatically, and any new native or iOS app in the
    org shows up here on its own. macOS apps are Apple-notarized and self-installing; iOS apps
    open in the App Store (or TestFlight while in beta); every web app link is live — tap to
    open. Ordered by whatever changed most recently. &nbsp;·&nbsp; Team only; don't share.
  </p>
</div></body></html>"""


if __name__ == "__main__":
    main()
