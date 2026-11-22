# 0.7.0-beta.1

First beta package from the 0.7.0 Team-contest baseline. This bump changes the in-game credit and addon metadata to **CraftyMonkeyButter** and does not change the contest protocol (schema 8) or gameplay.

## Before calling it stable
- Run an actual Retail Team contest using matching clients. Verify three complete teams, leadership nomination and acceptance, scoring, and agreed results. The prior eight-client simulation is not a live test.
- In a real contest, verify the full-outfit preview on host and contestant views after each turn and at voting. Confirm the fallback when the outfit cannot be reproduced.
- Verify the tested Retail version before tagging the CurseForge upload; this TOC targets interface 120105, not an untested later client.

## Rejection fix
The prior upload's screenshot lists blacklisted paths under `__MACOSX/`. Those are hidden duplicates created by macOS compression, not the runtime files required by the addon. Build a clean archive from the explicit runtime manifest and upload the resulting ZIP as-is. The release archive omits developer and tester docs, old ZIPs, Finder metadata, and source-control files; all authored docs remain in the repo. Do not delete the existing CurseForge project to retry one rejected file.
