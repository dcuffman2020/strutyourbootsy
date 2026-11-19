# DEV-02: Raid communication and authority

Status: **partial implementation**. The pure Lua authority gate is implemented and requires standalone test execution and live WoW verification. No wire protocol or transport is enabled yet.

## Authority contract
- Raid leader GUID, verified against the current live raid roster, is the only administrator.
- The admin cannot register as a contestant or submit ballots.
- Sender GUID must be resolved by the WoW event adapter using authenticated roster identity, never from untrusted message fields.
- Only confirmed addon clients may submit protocol messages; non-addon raid members remain passive observers.
- Session IDs prevent cross-contest messages; per-sender monotonic sequence numbers reject replay.
- Validate first, apply domain action second, advance sequence only after successful application.
- Leader transfer invalidates administrative commands and must pause/end per approved policy.
- Ballots remain administrator-local; only aggregates may be broadcast.

## Remaining engineering work
1. Verify the current Retail addon communication APIs and transport limits in-game.
2. Build prefix registration and bounded serialization/framing with strict field and payload validation.
3. Implement live raid roster GUID mapping and addon HELLO discovery/registration deadlines.
4. Bind domain transitions to validated admin commands; avoid trusting remote role claims.
5. Add heartbeat/disconnect detection, explicit pause and five-minute admin timeout.
6. Add state replication and designated recovery clients without copying identifiable ballots.
7. Integration tests with one administrator, five contestants, two spectators, and passive non-addon observers.

## UX independence
This module has no Figma dependency. UI will subscribe to validated state events after the protocol and product interaction contract are reconciled.

## Registration prototype implemented (not yet verified in game)
- Raid leader: `/syb host 1` through `/syb host 5` to announce a registration session.
- Other addon-equipped raid members: `/syb join contestant` or `/syb join spectator`.
- Leader applies REGISTER only after roster-GUID validation; peer role comes from a constrained protocol field.
- Leader sends REG_ACK; receiving peers accept it only from the roster-verified leader.
- `/syb status` reports registration counts and start eligibility **without starting a contest**.
- Repeated registration requests with a higher sequence and unchanged role re-send acknowledgment.
- `/syb refresh` re-announces the session for late joiners.
- A leader change blocks authoritative registration and start eligibility.

## Known limitations before alpha acceptance
- No timed heartbeat, periodic retries, reliable snapshot/sync, or persisted recovery; a missed announcement or ACK requires manual retry.
- Live client roster synchronization and communication remain untested.
- Peer ACKs are not yet a complete replay-protected replicated state log.
- START, BALLOT, all runtime stages, and voting are deliberately disabled.
- Registration counts may change as addon discovery resolves; the minimum-five and pending-users gates must be retested live.

## Reliability increment (2026-11-18)
- Registration requests are retried every 8 seconds until the leader's verified ACK is observed. Repeats get fresh sequence numbers and cannot change an accepted role.
- Administrator reannounces an active registration session every 20 seconds to help late addon clients discover it.
- Network adapter observes connection-status changes; original administrator disconnect suspends registration immediately.
- A 300-second administrator absence ends the registration session. Leadership transfer ends the old session immediately.
- Resuming a suspended session requires the original leader to enter `/syb resume-registration`; ended sessions are not recoverable.
- `/syb status` refuses to mark a suspended or ended registration eligible.
- Pure Lua deterministic retry/timeout tests: `tests/sync_spec.lua`.

### Still outstanding
This is **not full state recovery**. There is no persistent authoritative snapshot, receipt-verified replicated state log, automatic post-reload restoration, or designated-client takeover. Registration must not be treated as production-ready without a real multi-client test. Periodic retries and WoW message enqueue results do not guarantee delivery.

## Snapshot consistency design increment
- `Snapshot.lua` projects a copy of the administrator's **registration-only** state. The projection includes session ID, admin GUID, version, round count, phase, and sorted GUID/role pairs. It deliberately excludes individual ballots, scores, and mutable references to the authoritative contest engine.
- Replica acceptance requires the *adapter* to verify sender GUID against the current raid leader. The pure-Lua module rejects stale versions, nonconsecutive updates, unauthorized sources, and equal-version content conflicts.
- Version conflicts fail closed; a resync/recovery workflow must resolve them explicitly.
- `tests/snapshot_spec.lua` covers unauthorized senders, stale/gap behavior, conflicting replicas and deep-copy isolation.
- The module is loaded but **is not connected to addon messages**. No claim of synchronized or recovered multiplayer state is made at this point.

### Transport and recovery still required
Implement chunked bounded serialization; receipt validation and acknowledgments; snapshot request/retry; snapshot expiry and authoritative replacement rules; designated recovery holders; persist/restore after `/reload`; confidential vote data separation; and live multi-client acceptance. The current 180-character payload field cannot carry a full raid snapshot directly.

### Validation limitation
The GitHub branch was inspected through the connected GitHub service. The execution container has a LuaTeX interpreter but cannot resolve GitHub's hostname; consequently the branch could not be cloned for a complete executable test run. All snapshot tests remain authored but unverified.

## Bounded snapshot codec (implementation increment)
- `SnapshotCodec.lua` serializes the registration-only `Snapshot.lua` projection without executable deserialization.
- Splits data into up to 64 fragments of 120 payload bytes, each inside the existing 180-character protocol payload budget.
- Out-of-order fragments are assembled only after all pieces arrive. Identical retransmissions are accepted; conflicting duplicates, mixed transfer IDs and checksum mismatches fail closed.
- Assembly deliberately stays in memory and is not wired to `Network.lua` yet; no live snapshot send, resync, receipt, timeout eviction, or full-session recovery is claimed.
- The rolling checksum detects accidental corruption but **is not cryptographic authentication**; roster GUID and session authorization must be enforced in the transport adapter, and malicious in-group addon clients remain a threat model.
- Added `tests/snapshot_codec_spec.lua` for out-of-order, duplicates, corruption, malformed fields and maximum raid registration count. Tests authored but not executed.

## Network snapshot integration increment
- `SnapshotTransport.lua` connects the registration projection and fragment codec through `Main.lua` using the existing verified raid message adapter.
- New `SNAP_REQ`, `SNAP_PART`, and `SNAP_ACK` messages allow participants to request state, receive bounded fragments, and acknowledge a completed version.
- Administrator broadcasts snapshot fragments at a controlled cadence while registration remains active; a successful registration updates the queued snapshot.
- Incoming fragments must come from the currently verified raid leader matching the expected session's admin GUID. Invalid fragments, version gaps, and conflicts do not silently replace trusted state. Version gaps trigger a fresh replica request.
- Participants request current state periodically; the leader records received version ACKs for diagnostics, not delivery guarantees.
- New `tests/snapshot_transport_spec.lua` covers receiving, source rejection, ACK version and resync reset.
- No individual ballots or voting state are serialized or transmitted.

### Remaining reliability gates
1. Execute **all** Lua specs and fix actual failures.
2. Test interleaved/new snapshot transfers, packet loss, duplicate fragments, peers joining late, and reconnects with real WoW clients.
3. Add per-recipient transfer IDs, receipt-based delivery tracking, controlled retry/backoff, and bounded resource/timeout policies for partial assemblies.
4. Add explicit synchronized pause/recovery and safe persistent snapshots for reloads; current peer replication is in-memory only.
5. Check real WoW addon API return codes, packet size, message throttling and protocol behavior on the current Retail build.
6. Until those gates pass, no registration or snapshot flow should be considered release-ready; active gameplay phases remain disabled.

## Automated testing baseline (2026-11-18)
- GitHub Actions workflow `.github/workflows/lua-tests.yml` runs every `tests/*_spec.lua` with Lua 5.1 and 5.4 on pushes to the engineering branch and relevant pull requests.
- Initial CI run 44436322087: both Lua 5.1 and Lua 5.4 jobs passed.
- Passing standalone tests does not prove WoW Retail event/API correctness or multiplayer reliability. Live raid acceptance is still outstanding.
