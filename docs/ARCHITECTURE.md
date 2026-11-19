# Architecture and UX integration contract

Status: **foundation / alpha**, 2026-11-18. This is not a finished multiplayer addon.

## Ownership and boundaries
- UX workstream: Figma source designs, copy, interactions, visual tokens, accessibility decisions.
- Engineering workstream: Lua domain engine, WoW events, communications, validation, tests, packaging.
- Shared contract: this document and the approved product specification. A draft Figma design is not an implementation approval.

## Layers
1. `Core.lua`: pure Lua domain rules; accepts explicit player identities and state; no frames or game APIs.
2. `Network.lua`: injected, headless-testable roster and transport adapter. It owns bounded schema v1 messages, live sender/leader checks, discovery, session/version/command IDs, replay protection, acknowledgements and readonly lobby projections.
3. `Main.lua`: game entrypoint, minimal developer commands and the only binding from `Network.lua` to Retail APIs/events.
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

## DEV-02 delivery policy
- Multiplayer remains dormant until the verified raid leader explicitly runs `/syb devnetstart`; this is a development smoke-test command, not a production contest Start.
- The `SYBDEV02` protocol is schema-versioned and limited to WoW's 255-byte addon-message ceiling. It uses no optional serialization library.
- Outgoing traffic is capped at eight messages per rolling five-second window per client. Incoming packets are size/schema/field checked before use. The live transport sender is reconciled against the current full-name + GUID roster entry; payload identity claims convey no authority.
- Calling `C_ChatInfo.SendAddonMessage` only produces `queued`. A client mutation remains `pending` until a validated ACK or newer authoritative STATE arrives. Retries reuse the same command ID, and leaders cache 128 command results for idempotent replay handling.
- Discovery lasts ten seconds. A HELLO identifies an addon-equipped member as pending until role confirmation. Silence remains unknown and continues to block Start; it is never treated as proof that the addon is absent. A separate higher-level workflow may confirm a passive observer only against the member's current live GUID.
- The leader begins discovery with HELLO. A participant answers by WHISPER; the leader replies with a GUID-bound WELCOME carrying the current session ID, version and phase. Only that validated WELCOME may bootstrap a fresh participant session.
- Successful command ACKs must carry `ok` and exactly the request's expected version plus one. Rejections never advance client state, and replayed command results retain their original response version.
- Leader transfer emits `authority_changed`, pauses, and then ends the session. It never silently transfers the old session's authority.
- Only sanitized phase/session/version/presence projections are distributed. There is no ballot message type and no voter-to-rating payload route.

## Implementation decisions
- The adapter validates GUID/full realm-qualified name against the live raid roster and distinguishes detected pending users, passive observers, disconnected members and late joiners.
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
Positive no-addon classification beyond timeout inference, complete state snapshots/recovery integrity, random runway order, theme system, timed transitions, production command coordination, anonymous aggregate delivery, per-character settings, voting finalization, deterministic tie-break, disconnect recovery, reduced motion/contrast and distribution packaging.
