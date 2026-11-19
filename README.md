# Strut Your Bootsy

A community-driven **World of Warcraft Retail transmog contest addon**.

**Status:** Pre-alpha, engineering foundation. Not ready for live raid contests.

## Workstreams
- **UX:** Figma owns approved interaction models and visual design.
- **Engineering:** GitHub owns Lua, technical specifications, validation and release history.
- The two workstreams can proceed in parallel; `docs/ARCHITECTURE.md` defines the integration boundary.

## Current implementation
- Retail addon manifest for interface `120105` (12.1.5).
- Headless Lua domain engine: contestant/spectator registration, minimum five contestants, 1–5 rounds, phase transitions, partial 1–5 rating ballots, no self-voting, averaged round results, final eligibility and pause/resume.
- Developer-only local commands: `/syb status`, `/syb devstart`.
- Pure Lua tests: `lua tests/core_spec.lua` (not executed yet).

## Not implemented yet
Raid communication, authenticated raid membership, addon-user discovery, admin reconciliation, runway ordering, voting UI, timers, themes, tie-break procedure, recovery, polished visuals and packaging.

Do **not** rely on the current Lua core as proof of a secure multiplayer experience: the integration layer must authenticate sender identity and roster membership.

## Development
Clone this repository into `World of Warcraft/_retail_/Interface/AddOns/StrutYourBootsy` for local testing. In game, run `/dump select(4, GetBuildInfo())` to confirm the client interface number and `/syb status` to confirm the loader.

See [architecture and UX contract](docs/ARCHITECTURE.md).

## Contribution workflow
Implement features on branches and use pull requests. Keep final Figma styling separate from the domain layer. Do not merge before relevant checks and gameplay verification.
