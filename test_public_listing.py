#!/usr/bin/env python3
"""INT-001. Screen Studio stays in the catalog and off the public page.

Does not call GitHub. Run from this directory: python3 test_public_listing.py
"""
import json
import os

import gen

HERE = os.path.dirname(os.path.abspath(__file__))


def test_filter_keeps_team_and_hides_internal():
    apps = [
        {"name": "NSM Screen Studio", "access": "internal"},
        {"name": "Prism", "access": "public"},
        {"name": "GrabIt", "access": "team"},
    ]
    names = [a["name"] for a in gen.listed_apps(apps)]
    assert names == ["Prism", "GrabIt"], names


def test_page_no_longer_offers_screen_studio():
    page = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
    assert "NSM Screen Studio" not in page
    assert "NSM-Screen-Studio-mac.dmg" not in page
    assert 'Mac apps <span class="n">14</span>' in page
    mac = page.split("<h2>", 2)[1]
    assert mac.count('class="card"') == 14


def test_catalog_still_claims_the_repo():
    catalog = json.load(open(os.path.join(HERE, "catalog.json"), encoding="utf-8"))
    match = [a for a in catalog["apps"] if a["name"] == "NSM Screen Studio"]
    assert len(match) == 1
    assert match[0]["access"] == "internal"
    assert match[0]["repo"] == "jasonzacmusic/nsm-screen-studio"


def test_discover_does_not_publish_a_second_card():
    gen.hub_assets = lambda tag="downloads": set()
    gen.repo_meta = lambda repo: ("2026-09-29T08:17:00Z", "note")
    gen.languages = lambda full: {"Swift": 1} if full.endswith("nsm-screen-studio") else {}
    gen.native_from_release = lambda full: (
        {"mac": "https://example.invalid/old.dmg"} if full.endswith("nsm-screen-studio") else {}
    )
    gen.detect_ios = lambda full, langs: False

    def gh(args):
        if args[:3] == ["repo", "list", gen.ORG]:
            return [{"name": "nsm-screen-studio", "homepageUrl": "", "pushedAt": "2026-09-29T08:17:00Z"}]
        raise AssertionError("unexpected GitHub call: " + " ".join(args))

    gen.gh_json = gh
    gen.CURATED_ONLY = False
    apps = gen.build()
    claimed = [a for a in apps if a.get("repo") == "jasonzacmusic/nsm-screen-studio"]
    assert [a["name"] for a in claimed] == ["NSM Screen Studio"], [a["name"] for a in claimed]
    assert claimed[0]["access"] == "internal"
    shown = [a["name"] for a in gen.listed_apps(apps)]
    assert "NSM Screen Studio" not in shown
    assert "Nsm Screen Studio" not in shown
    assert "Prism" in shown
    assert "GrabIt" in shown


if __name__ == "__main__":
    test_filter_keeps_team_and_hides_internal()
    test_page_no_longer_offers_screen_studio()
    test_catalog_still_claims_the_repo()
    test_discover_does_not_publish_a_second_card()
    print("public listing checks passed")
