# DEV-02 — Codex Engineering Work Order

**Status:** Ready for local Codex execution; no implementation has been asserted as complete.
**Working branch:** `feature/dev-02-raid-comms`
**Base:** `docs/sync-01-unified-contract` (stacked above foundation PR #1; see draft PR #3).
**Canonical product/UX contract:** [UX_ENGINEERING_CONTRACT.md](UX_ENGINEERING_CONTRACT.md).
**Trello:** https://trello.com/c/pc9LDuMr
**Figma:** https://www.figma.com/design/c2Qaeb9hHOcYtdtPXAi8Vl/Strut-Your-Bootsy-UX

## Objective
Create the first safe, testable multiplayer *infrastructure* for a retail WoW transmog-contest addon, without exposing incomplete UI or pretending the alpha is playable. Implement headless WoW API adapters and pure-Lua test seams where practical. Preserve Core.lua as game-API-independent. Do not rework Figma or approved MVP 2.1 requirements.

## First-step environment and baseline gate
1. Inspect repository status, `StrutYourBootsy.toc`, `Core.lua`, `Main.lua`, `docs/ARCHITECTURE.md`, and `docs/UX_ENGINEERING_CONTRACT.md`. Confirm the local checkout is this branch, no unrelated changes, and do not change main or merge PRs.
2. Run `lua tests/core_spec.lua` with a Lua 5.1-compatible runtime. If unavailable, report that explicitly; do not claim tests passed. Add compatibility-safe tests; do not silently install or alter unrelated dependencies.
3. Verify existing `## Interface: 120105` is appropriate for the user's actual current WoW Retail client when testing locally. Do not invent a verified interface build.
4. Inspect which retail addon APIs are actually available. Prefer built-in C_ChatInfo / event hooks with scoped feature detection. Keep all game API access out of Core.lua. No automatic protected game actions.

## Scope for first implementation PR
### 1. Network protocol + limits
- Add `Network.lua` (and optionally small modules if separation is justified), included in the TOC in load order.
- Register a unique, valid addon-message prefix; implement bounded, schema-versioned commands over WoW addon messages. Check payload byte length and validate each command before use; avoid assuming serialization libraries are installed. Rate-limit and bound outgoing/incoming messages, with a documented delivery policy.
- Message types: HELLO / capability discovery; authoritative state snapshot / versioned update; command request / acknowledge / reject; heartbeat/presence if justified. Keep message types small; never broadcast identifiable ballots.
- Include session ID, monotonic state version, command ID; reject stale sessions, duplicate/replayed command IDs, unknown commands, badly typed fields, oversized payloads, unauthorized senders, wrong-phase mutations.
- Do not claim network delivery on merely calling a Send API. Surfacing successful state requires a validated authoritative acknowledgment.

### 2. Identity, roster, and admin authority
- Build an adapter for raid roster + live player GUID/full realm-qualified identity. Distinguish detected compatible addon users, pending role response, passive no-addon members, disconnected participants and late joiners.
- The actual sender must come from addon transport + live raid roster; never accept a claimed sender/admin string at face value.
- Admin is the current raid leader. Never permit a non-leader to start, pause, advance, end, vote as admin, or issue admin-only commands. Raid leader cannot participate or vote.
- Detect roster/leader changes and report an explicit event/state to the session coordinator; leadership transfer pauses then ends by approved policy rather than silently promoting a new leader.
- Pending *detected addon-equipped* users block registration Start; truly no-addon raid members remain passive observers. A lack of response cannot alone be confidently interpreted as a no-addon state: document discovery timeout/unknown classification and conservative behavior.

### 3. Lifecycle scaffold
- Keep multiplayer dormant unless a verified leader explicitly initiates a dev session; preserve `/syb status` and `/syb devstart` semantics as local developer-only behavior, or add a clearly named separate explicit command for network smoke testing. Do not expose production contest start without gates.
- Provide clear diagnostics for raid membership, detected users, authority, current session ID/version and last rejected command reason, without leaking ballots. Ensure event registration/reloads do not double-register listeners.

### 4. Tests and evidence
- Write deterministic Lua tests using stubbed WoW APIs for authorized vs spoofed senders; out-of-raid sender; changed raid leader; duplicate/replayed/stale command; malformed/oversized payload; late join/no-addon vs pending addon; wrong phase; transport failure and retry/idempotency boundaries.
- Test at least two simulated addon clients in headless tests where feasible, then produce a separate in-game two-client verification checklist (leader + participant).
- Check that no public message exposes voter-to-rating details. Preserve anonymous aggregate rule.
- Record exact commands run and outcomes. If the runtime or in-game WoW are unavailable, list these as **Not run**, not Pass.

## UX integration handshake
Implement readonly projections (not Figma styling) for lobby screen states: `insufficient_contestants`, `pending_addon_users`, `not_raid_leader`, `ready_to_start`, `passive_observer`, `late_joiner`, `disconnected`. Use last-confirmed authoritative state. Figma A01 voting and A03 disconnect UI are still open audit work; define event hooks but do not invent those screens.

## Explicit exclusions in this slice
No entire wizard, themed skins, portrait assets, voting form, full scoring UI, awards, advanced recovery snapshot, automatic protected-action execution, CurseForge packaging, or public alpha claim. Address critical security issues that block safe authority testing before expanding scope.

## Acceptance
- Lua compatibility and headless tests with actual execution evidence.
- A local raid leader and addon-equipped participant can discover each other, exchange a versioned sanctioned message and receive verified state/ack; outsider and impersonation requests rejected.
- A local non-leader cannot take administrator actions; leader change invalidates prior authority.
- Protocol is bounded and defaults to fail closed for unknown/malformed requests; no private ballots leaked.
- Draft PR with changed files, tests run and real WoW test checklist. Don't merge or mark Trello Done without review.

## Workflow safeguards
Keep this branch isolated from other work; commit in small coherent steps. Preserve the agreed Figma Direction B and the Bootsy mascot accent. Do not alter Figma in Codex. Report real implementation results rather than completion estimates.
