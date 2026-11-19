# Architecture and UX integration contract

Status: **foundation / alpha**, 2026-11-18. This is not a finished multiplayer addon.

## Ownership and boundaries
- UX workstream: Figma source designs, copy, interactions, visual tokens, accessibility decisions.
- Engineering workstream: Lua domain engine, WoW events, communications, validation, tests, packaging.
- Shared contract: this document and the approved product specification. A draft Figma design is not an implementation approval.

## Layers
1. `Core.lua`: pure Lua domain rules; accepts explicit player identities and state; no frames or game APIs.
2. `Main.lua`: game entrypoint and minimal developer commands; future adapter to WoW events.
3. Future `Network.lua`: registered addon prefix, serialized short messages, RAID/WHISPER transport, roster authorization, admin-authoritative versioned state replication and recovery.
4. Future `UI/`: subscribes to domain events and renders Figma-approved flows without mutating state directly.

## Agreed policy baseline
- Administrator is the raid leader and cannot compete or vote.
- Minimum five registered contestants; responding addon users choose contestant or spectator.
- Raid members without the addon are passive observers. They cannot vote or compete and must not block start.
- Non-responding addon users block start.
- One to five rounds; a 1–5 rating per contestant, optional/partial ballots, no vote revision or self-rating.
- Voting remains open until closed by the authorized workflow; results only computed after close.
- A contestant must receive a score in every round to qualify for final placing.
- First/second/third-place ties require a separately verified /roll 100 resolution; fourth place is honorable mention.
- Pausing, admin disconnect, contestant disconnect and leader transfer are handled by a future event adapter/state supervisor.

## Implementation decisions
- **No network behavior is shipped in this initial slice.** Pure Lua functions do not establish sender authenticity.
- The eventual adapter must validate GUID/full realm-qualified name against live raid roster and distinguish addon users from passive observers.
- Incoming addon messages must be treated as untrusted input. Never let clients claim administrator authority merely by naming themselves as admin.
- Addon messages have a 16-character prefix limit and 255-byte message limit; use bounded transport, validation and throttling.
- Never send identifiable ballots to other participants; only administrator state may have individual ballots, with aggregate results shared.
- Score averages are per-rated-contestant per-round; UX and spec must agree on handling abstentions and tied rankings before release.
- Recovery snapshots require strict session IDs, monotonically increasing versions and integrity checks before resumption.
- No addon component should automate protected actions or access restricted game state.

## Engineering acceptance gates
1. Pure Lua rules covered by tests (normal, rejected, boundary, and tie cases).
2. Retail load test: current interface metadata confirmed with `/dump select(4, GetBuildInfo())`.
3. Multiplayer test: admin + at least five contestants + two spectators, including absent-addon observers.
4. Disconnect and leader-transfer validation.
5. UX acceptance against approved Figma flows.
6. Security and CurseForge packaging review.

## Open / future engineering items
Random runway order, theme system, timed transitions, admin-authorized commands, reliable messaging, anonymous delivery, per-character settings, voting finalization, deterministic tie-break, disconnect recovery, diagnostics, reduced motion/contrast and distribution packaging.
