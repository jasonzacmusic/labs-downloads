# Nathaniel Labs — internal downloads hub

Run ./publish.sh after any app rebuild. It uploads the latest installers to the GitHub
Release (stable URLs) and redeploys the page. Team visits:
https://jasonzacmusic.github.io/labs-downloads/

## Core Mac app release gate

GrabIt, MIDI Piano Visualizer, Shruti, and Sangam are not released until all four surfaces
agree: the source tag/release, the exact stable installer on this hub, the product registry,
and the live Nathaniel Labs product page. The release task must regenerate the hub and Labs
site locally, verify the live version and installer hash, and only then report completion.

The zero-cost default is event-driven: release dispatches and manual fallback only. Do not
add polling or scheduled Actions, and do not use paid macOS runners for these locally built,
signed, and notarized apps.

Incoming installer branches trigger by push or a single `receive-build` repository dispatch.
The former five-minute sweep and daily hub scan are intentionally disabled.
