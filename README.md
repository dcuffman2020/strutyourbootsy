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
- Headless-testable DEV-02 network/roster adapter: bounded schema, live roster/leader authorization, discovery/presence, versioned idempotent commands, ACK/reject handling, leader-change termination and readonly lobby projections.
- Developer-only commands: `/syb status`, `/syb devstart`, and leader-only `/syb devnetstart` network smoke testing.
- Pure Lua tests: `lua tests/core_spec.lua` and `lua tests/network_spec.lua`.

## Not implemented yet
Production contest coordination, positive no-addon classification, complete recovery snapshots, runway ordering, voting UI, timers, themes, tie-break procedure, polished visuals and packaging.

Do **not** treat the development network scaffold as a playable alpha. It provides fail-closed authority and transport seams but intentionally exposes no production contest start or voting route.

## Development
Clone this repository into `World of Warcraft/_retail_/Interface/AddOns/StrutYourBootsy` for local testing. In game, run `/dump select(4, GetBuildInfo())` to confirm the client interface number and `/syb status` to confirm the loader.

See [architecture and UX contract](docs/ARCHITECTURE.md).

## Contribution workflow
Implement features on branches and use pull requests. Keep final Figma styling separate from the domain layer. Do not merge before relevant checks and gameplay verification.
