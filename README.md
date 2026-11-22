# Strut Your Bootsy

A standalone **World of Warcraft Retail transmog contest addon**. Host a solo or team runway contest, review presented outfits, and collect timed ratings.

**Current build:** 0.7.0-beta.1 (Retail interface 120105). The beta is for testing, not a stable-release claim. Automated Lua workflows pass; live Retail Team contests and full-outfit model fidelity still need verification. See the [beta notes](docs/BETA_0_7_0.md).

## Try it in WoW
- Install the single `StrutYourBootsy/` folder inside Retail’s `Interface/AddOns/`. Avoid a second folder layer.
- Use `/syb` or the minimap icon. Outside a raid, use Practice Mode or `/syb teampractice` to try Team mode with fictional contestants.
- For a real raid, use the same build on every client. The raid leader officiates and cannot vote. Solo needs five contestants; Team mode needs three complete teams of the selected size. You cannot rate your own entry.

## Development
- The Lua tests in `tests/*_spec.lua` cover rules, registration, rendering through a mock client, and multiplayer communication through a simulation.
- `docs/TEAM_MODE_SPEC.md` describes the Team rules. `docs/ALPHA_TESTER_GUIDE.md` documents earlier test flows. Older milestone docs describe their specific snapshots.
- The runtime ZIP contains only the TOC, Lua source, and UI textures under `StrutYourBootsy/`. Do not re-compress an unpacked copy in Finder for CurseForge.

Made by CraftyMonkeyButter.
