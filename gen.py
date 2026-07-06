#!/usr/bin/env python3
"""Generate the Nathaniel Labs internal downloads hub.

Reads catalog.json, asks GitHub for each app's latest activity (pushed_at + latest commit)
so the list is ordered by what changed most recently, resolves native installer links from
the labs-downloads release, and writes index.html. GitHub-date-driven: any push to any app
repo moves it to the top on the next run. Runs locally (uses `gh auth token`) or in GitHub
Actions (uses GITHUB_TOKEN). Standard library only.
"""
import json, os, subprocess, urllib.request, urllib.error, datetime, html

REPO = "jasonzacmusic/labs-downloads"
TAG = "downloads"
API = "https://api.github.com"


def token():
    t = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if t:
        return t
    try:
        return subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    except Exception:
        return ""


TOK = token()


def api(path):
    req = urllib.request.Request(API + path)
    req.add_header("Accept", "application/vnd.github+json")
    if TOK:
        req.add_header("Authorization", "Bearer " + TOK)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except Exception:
        return None


def hub_assets():
    d = api(f"/repos/{REPO}/releases/tags/{TAG}") or {}
    return {a["name"] for a in d.get("assets", [])}


def rel_time(iso):
    if not iso:
        return ("", "")
    try:
        t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except Exception:
        return ("", "")
    now = datetime.datetime.now(datetime.timezone.utc)
    secs = (now - t).total_seconds()
    if secs < 3600:
        s = f"{int(secs//60)}m ago"
    elif secs < 86400:
        s = f"{int(secs//3600)}h ago"
    elif secs < 86400 * 30:
        s = f"{int(secs//86400)}d ago"
    else:
        s = t.strftime("%b %-d, %Y")
    return (s, t.strftime("%Y-%m-%d %H:%M"))


PLAT = {"mac": "macOS", "win": "Windows", "linux": "Linux", "ipad": "iPadOS", "ios": "iOS", "web": "Web"}


CACHE_PATH = os.path.join(os.path.dirname(__file__), "state.json")
try:
    CACHE = json.load(open(CACHE_PATH))
except Exception:
    CACHE = {}


def enrich(app, assets):
    repo = app.get("repo")
    pushed = None
    commit = ""
    if repo:
        info = api(f"/repos/{repo}")
        if info:
            pushed = info.get("pushed_at")
        c = api(f"/repos/{repo}/commits/HEAD")
        if c:
            try:
                commit = c["commit"]["message"].splitlines()[0][:60]
            except Exception:
                pass
        # Graceful degrade: a runner that can't see this repo (e.g. the cloud with no
        # private-repo token) keeps the last known date/commit instead of blanking it.
        cached = CACHE.get(repo, {})
        if pushed:
            cached["pushed"] = pushed
        else:
            pushed = cached.get("pushed")
        if commit:
            cached["commit"] = commit
        elif not commit:
            commit = cached.get("commit", "")
        CACHE[repo] = cached
    # resolve downloads
    downloads = []
    for n in app.get("native", []):
        if n["asset"] in assets:
            downloads.append((n["platform"],
                              f"https://github.com/{REPO}/releases/latest/download/{n['asset']}"))
    app["_pushed"] = pushed or ""
    app["_rel"], app["_abs"] = rel_time(pushed)
    app["_commit"] = commit
    app["_downloads"] = downloads
    return app


def card(app):
    name = html.escape(app["name"])
    cat = html.escape(app.get("category", ""))
    rel, ab = app["_rel"], app["_abs"]
    commit = html.escape(app["_commit"])
    downloads = app["_downloads"]
    web = app.get("web")
    soon = app.get("soon")

    updated = f'<span class="upd" title="{ab}">updated {rel}</span>' if rel else ""
    commit_line = f'<p class="commit">{commit}</p>' if commit else ""

    # primary action + platform chips
    chips, actions = [], []
    for plat, url in downloads:
        chips.append(PLAT.get(plat, plat))
        actions.append(f'<a class="btn" href="{html.escape(url)}">{PLAT.get(plat, plat)} &darr;</a>')
    if web:
        chips.append("Web")
        actions.append(f'<a class="btn ghost" href="{html.escape(web)}" target="_blank" rel="noopener">Open &rarr;</a>')
    if soon and not actions:
        chips.append("iPadOS")
        actions.append(f'<span class="btn dim">{html.escape(soon)}</span>')

    chipline = " · ".join(chips)
    note = ' · notarized' if any(p == 'mac' for p, _ in downloads) else ''
    return f"""      <div class="card">
        <div class="row"><span class="name">{name}</span>{updated}</div>
        <p class="sub">{cat}{(' · ' + chipline + note) if chipline else ''}</p>
        {commit_line}
        <div class="acts">{''.join(actions)}</div>
      </div>"""


def main():
    cat = json.load(open(os.path.join(os.path.dirname(__file__), "catalog.json")))
    assets = hub_assets()
    apps = [enrich(a, assets) for a in cat["apps"]]
    # newest activity first; undated apps last
    apps.sort(key=lambda a: a["_pushed"], reverse=True)
    cards = "\n".join(card(a) for a in apps)

    host = os.environ.get("HUB_HOST") or subprocess.run(
        ["bash", "-c", "scutil --get ComputerName 2>/dev/null || hostname"],
        capture_output=True, text=True).stdout.strip() or "the cloud"
    updated = datetime.datetime.now().strftime("%B %-d, %Y at %-I:%M %p")

    page = TEMPLATE.replace("{{CARDS}}", cards).replace("{{UPDATED}}", updated).replace("{{HOST}}", html.escape(host))
    with open(os.path.join(os.path.dirname(__file__), "index.html"), "w") as f:
        f.write(page)
    json.dump(CACHE, open(CACHE_PATH, "w"), indent=0, sort_keys=True)
    print(f"generated index.html — {len(apps)} apps, ordered by latest GitHub activity")


TEMPLATE = """<!doctype html>
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
  .meta{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:12px;margin-top:12px}
  h2{font-family:'IBM Plex Mono',monospace;font-size:12px;font-weight:500;letter-spacing:2px;color:var(--faint);text-transform:uppercase;margin:36px 0 14px}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:14px}
  .card{display:flex;flex-direction:column;gap:7px;background:var(--card);border:.5px solid var(--line);border-radius:14px;padding:16px 18px}
  .row{display:flex;align-items:baseline;justify-content:space-between;gap:10px}
  .name{font-weight:600;font-size:17px}
  .upd{color:var(--green);font-family:'IBM Plex Mono',monospace;font-size:10.5px;white-space:nowrap}
  .sub{color:var(--mut);font-size:12.5px}
  .commit{color:var(--faint);font-family:'IBM Plex Mono',monospace;font-size:10.5px;line-height:1.4}
  .acts{display:flex;flex-wrap:wrap;gap:8px;margin-top:6px}
  .btn{font-size:13px;font-weight:500;text-decoration:none;color:var(--ink);background:var(--amber);padding:6px 12px;border-radius:8px}
  .btn.ghost{color:var(--amber);background:transparent;border:.5px solid var(--line)}
  .btn.dim{color:var(--faint);background:transparent;border:.5px solid var(--line);font-weight:400}
  a.btn:hover{opacity:.9}
  .note{margin-top:40px;color:var(--faint);font-size:12.5px;line-height:1.7;border-top:.5px solid var(--line);padding-top:18px}
</style></head><body><div class="wrap">
  <div class="brand"><span class="amber">Nathaniel</span> Labs</div>
  <div class="tag">Internal builds — ordered by whatever changed most recently.</div>
  <div class="meta">Refreshed {{UPDATED}} · from {{HOST}}</div>
  <h2>All apps · newest first</h2>
  <div class="grid">
{{CARDS}}
  </div>
  <p class="note">
    Each app shows when its code last changed on GitHub and its latest commit, so the freshest
    work is always on top. macOS apps are Apple-notarized and self-installing. iPad/iOS apps
    arrive via TestFlight. &nbsp;·&nbsp; Team only; please don't share the link.
  </p>
</div></body></html>"""


if __name__ == "__main__":
    main()
