# Strut Your Bootsy

A standalone **World of Warcraft Retail transmog contest addon**. Host a solo or team runway contest, review presented outfits, and collect timed ratings.

**Version:** 1.0.0 for WoW Retail 12.1.5 (interface 120105). Run up to five rounds in Solo or Team mode. See the [changelog](CHANGELOG.md) and [release checklist](docs/CURSEFORGE-1_0_0.md).

## Try it in WoW
- Install the single `StrutYourBootsy/` folder inside Retail’s `Interface/AddOns/`. Avoid a second folder layer.
- Use `/syb` or the minimap icon. Outside a raid, use Practice Mode or `/syb teampractice` to try Team mode with fictional contestants.
- For a real raid, use the same build on every client. The raid leader officiates and cannot vote. Solo needs five contestants; Team mode needs three complete teams of the selected size. You cannot rate your own entry.

## Rounds and results
- Choose one to five rounds when setting up live registration. Each round has its own presentation and anonymous 1–5 star ballot. A submitted ballot is final; you can leave individual entries unrated.
- Final scores use each entry’s unrounded round averages, weighted equally across rounds. An entry must earn a score in every round to place overall.
- The raid leader resolves podium ties before confirming and revealing awards. All clients in a live contest must run a matching version; do not mix 1.0.0 with beta clients. If the raid leader fully logs out or reloads WoW, start a new contest; the old host session cannot be transferred.

## Development
- The Lua tests in `tests/*_spec.lua` cover rules, registration, rendering through a mock client, and multiplayer communication through a simulation.
- `docs/TEAM_MODE_SPEC.md` describes the Team rules. `docs/ALPHA_TESTER_GUIDE.md` documents earlier test flows. Older milestone docs describe their specific snapshots.
- The runtime ZIP contains only the TOC, Lua source, and UI textures under `StrutYourBootsy/`. Run `python3 scripts/package.py` to build and verify it. Do not re-compress an unpacked copy in Finder for CurseForge.

Made by CraftyMonkeyButter.
