# SYNC-01 — Unified UX / Engineering Contract
Status: **proposed integration contract, pending gameplay verification**. Updated 2026-11-18.
Sources: approved MVP 2.1 epics (EP-01–EP-15), Figma UX audit A01–A11, 35 UX wireframes, HI-01–HI-04B, and foundation PR #1. This document does not supersede approved product decisions.

## Ownership / implementation boundary
- **Figma** controls presentation, interaction affordances, role copy, accessibility, and screens; approved visual direction is **B: Warm & Welcoming**. Bootsy is an unobtrusive mascot. A later visual-theme choice cannot change semantic interaction.
- **Core.lua** controls UI-independent rules and phase transitions; game APIs must not be introduced into this domain layer.
- **WoW adapter / Network.lua (DEV-02)** controls identity, authoritative sender verification, addon capabilities, session IDs, ordered versions, raid roster updates, disconnect and time synchronization, and reliable bounded transport.
- **UI/** derives every displayed state/action from the **last confirmed authoritative state**; never signal that a mutation succeeded before administrator confirmation.
- **Trello** controls prioritization and acceptance; GitHub PR review controls code integration. No implementation is automatically approved merely because it appears in Figma.

## Shared model
All messages are untrusted. Authoritative mutable session state lives with the current raid leader; clients receive a sanitized projection. Each command carries bounded schema version, session ID, unique command ID, expected version, and payload. The adapter infers sender from transport metadata and roster; it MUST NOT trust claimed sender/admin identity in payload. Reject stale sessions, replayed command IDs, wrong phases, malformed or oversized payloads, unknown users and unauthorized commands. Never broadcast identifiable individual ballots; only aggregates and viewer-relevant ballot confirmation.

Identity = full realm-qualified player name plus live roster GUID where available, revalidated on roster changes. Presence states: addon-ready, addon-pending, no-addon/passive observer, disconnected, late-joiner observer. Do not equate non-response with no addon until discovery policy establishes classification; do not misclassify non-responding detected addon clients as passive. Pending addon-equipped members block start; passive non-addon members do not.

**Phases:** registration -> preparation -> runway -> voting -> round_results -> preparation (next round) OR final_results -> ended. Paused is an overlay on a saved prior phase; explicit authorized resume restores the saved phase, never guesses it. Distinguish disconnected-admin timeout, leadership transfer and inconsistent-snapshot cancellation from ordinary pause.

**Eligible actions by phase / role**
| Phase | Administrator | Contestant | Spectator | Passive no-addon raid member |
|---|---|---|---|---|
| registration | Configure, inspect readiness, start only when all gates pass, cancel | Confirm contestant role | Confirm spectator role | No interaction |
| preparation | Begin runway per approved timer/workflow; pause | Read theme and prep status | View status | No interaction |
| runway | Advance one contestant manually; begin voting only after all presentations; pause | Observe current contestant | Observe | No interaction |
| voting | Observe timer and completion; pause (no ballot) | Submit single partial ballot excluding self | Submit single partial ballot | No interaction |
| round_results | View aggregates, start next round only after voting has closed | View aggregates | View aggregates | No interaction |
| final_results | Resolve podium ties via verified /roll 100 procedure and confirm awards | View result | View result | No interaction |
| paused/recovery | Explicit resume if consistent and authorized; cancel/end where required | Read recovery status | Read recovery status | No interaction |

**Action results:** pending (submitted but unconfirmed), acknowledged, rejected (typed reason), timeout/retry, cancelled. Command retry must be idempotent. Last-confirmed authoritative state version determines button enabled state. Required errors: not_raid_leader, insufficient_contestants, pending_addon_users, wrong_phase, duplicate_ballot, self_vote, voting_closed, disconnected, authority_changed, snapshot_mismatch, unsupported_client.

## P0 UX audit remediation contracts
**A01 — Voting** (UX-07, 21–23, HI-03): each round displays all contestants for a 1–5 star selection per contestant; contestant's own row is unavailable. Partial ballots/abstentions allowed, but an empty submission is not a ballot. Submit is final: no revision. Keep voting open to timer expiry even if all ballots are in. Distinguish editing, sending, accepted, rejected, countdown-expired states. Individual ballot and voter identity must not appear in participant-facing aggregates. Admin cannot vote. Server-authoritative timer and close gate control round progression.

**A02 — Registration readiness** (UX-03–04, 17–19, 32, HI-02): disabled Start conveys actionable reason: <5 contestants, detected addon-equipped users still awaiting role, and non-admin attempting start. Explicitly distinguish passive no-addon observers and late joiners from pending addon-equipped users. Start enabled only when leader + five or more contestants + no pending addon-equipped members + valid raid/session state. Don't assume roster discovery is instant.

**A03 — Authority / disconnect recovery** (UX-10, 28–31): leadership transfer pauses then ends contest per approved policy (not automatic reassignment); raid leader disconnect pauses, then ends after five minutes if unresolved; contestant disconnect auto-pauses; resume requires explicit admin action plus verified authoritative replicated snapshot. A mismatch cancels rather than silently overwrites state. Recovery projection must exclude identifiable ballots unless narrowly required and expressly approved with documented privacy. Separate user-facing cause, timer, action availability, and failure messaging for each branch.

**A04 — Traceability**: map UX-01–35 and HI-01–04B below to canonical EP identifiers. The original Figma handoff's EP references were provisional and MUST NOT be treated as approved epic numbering.

## Canonical UX → EP mapping (cross references)
| Figma | Screen | Canonical epics | Primary implementation |
|---|---|---|---|
| UX-01 | Welcome / entry | EP-01, EP-11, EP-12 | Main, UI |
| UX-02 | Contest configuration | EP-03, EP-11 | Core, UI |
| UX-03 | Registration lobby | EP-02, EP-04, EP-11 | Network, UI |
| UX-04 | Choose your role | EP-04, EP-12 | Network, Core, UI |
| UX-05 | Theme reveal + preparation | EP-05, EP-06, EP-12 | Core, Timers, UI |
| UX-06 | Runway presentation | EP-07, EP-11 | Core, UI |
| UX-07 | Judge contestants | EP-08, EP-12 | Core, Network, UI |
| UX-08 | Round result + next round | EP-05, EP-09, EP-10 | Core, UI |
| UX-09 | Final awards | EP-09, EP-10 | Core, UI |
| UX-10 | Paused / recovery | EP-05, EP-13 | Network, Recovery, UI |
| UX-11 | Interface preferences | EP-14 | Settings, UI |
| UX-12 | Setup: round count | EP-03 | Core, UI |
| UX-13 | Setup: theme selection | EP-03, EP-06 | Themes, UI |
| UX-14 | Setup: preparation timer | EP-03, EP-05 | Timers, UI |
| UX-15 | Setup: voting timer | EP-03, EP-08 | Timers, UI |
| UX-16 | Setup: final review | EP-03, EP-11 | Core, UI |
| UX-17 | Lobby: awaiting response | EP-02, EP-04 | Network, UI |
| UX-18 | Lobby: minimum not met | EP-04 | Core, UI |
| UX-19 | Spectator participation | EP-04, EP-12 | Network, UI |
| UX-20 | Runway: participant view | EP-07, EP-12 | Core, UI |
| UX-21 | Voting: ballot in progress | EP-08, EP-12 | Core, UI |
| UX-22 | Voting: submitted | EP-08, EP-12 | Network, UI |
| UX-23 | Voting: timer expired | EP-05, EP-08 | Timers, Core, UI |
| UX-24 | Round completion gate | EP-05, EP-08, EP-09 | Core, UI |
| UX-25 | Final: tie resolution | EP-09, EP-10 | Roll verification, UI |
| UX-26 | Final: reveal sequence | EP-10, EP-12 | Core, UI |
| UX-27 | Admin: contextual console | EP-05, EP-11 | Core, UI |
| UX-28 | Admin disconnect | EP-13 | Network, Recovery, UI |
| UX-29 | Leadership changed | EP-02, EP-13 | Network, UI |
| UX-30 | Contestant disconnect | EP-13 | Network, Recovery, UI |
| UX-31 | Recovery integrity failure | EP-13 | Recovery, UI |
| UX-32 | Late joiner / no addon | EP-02, EP-04 | Network, UI |
| UX-33 | Diagnostics | EP-01, EP-13, EP-15 | Network, Diagnostics, UI |
| UX-34 | Preferences: accessibility | EP-14 | Settings, UI |
| UX-35 | Remove participant | EP-04, EP-11 | Core, Network, UI |
| HI-01 | Administrator console (Direction B) | EP-11 | UI |
| HI-02 | Role selection | EP-04, EP-12 | UI |
| HI-03 | Voting | EP-08, EP-12 | UI |
| HI-04 / HI-04B | Remaining approved high-fidelity concepts/variants | EP-07, EP-11, EP-12 (confirm exact node titles at visual acceptance) | UI |

## Engineering sequence and test gates
1. **Foundation:** execute Lua 5.1-compatible unit tests and current Retail addon load test; verify TOC interface value against actual running client. PR #1 remains draft until test evidence.
2. **DEV-02:** transport, live GUID/roster and raid-leader checks, handshake/capability discovery, versioned idempotent commands, bounded payload/acks/retries, rejected command diagnostics. No unauthenticated vote route.
3. **First playable vertical slice:** raid registration lobby with A02 behaviors; five or more contestants, spectator distinction, admin-only Start.
4. **Contest loop:** config/theme/prep -> randomized runway -> final contestant -> voting (A01) -> scoring -> results, with explicit transitions and timing tests.
5. **Resilience + acceptance:** A03 transitions and recovery; multi-client alpha: admin + five contestants + two spectators, including passive no-addon observer and late join cases. No P0 may remain for private-alpha acceptance. Verify against Figma.

Open validation items: exact scoring denominator and no-ratings qualification edge cases; command-retry policy; addon discovery timeout; API support of remote portrait SetPortraitTexture via unit token; current Retail API/version. These are implementation checks, not silent changes to approved decisions.
