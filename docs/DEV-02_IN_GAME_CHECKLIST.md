# DEV-02 two-client in-game verification

Status: **Not run** until recorded against an actual current WoW Retail client. Do not infer the current interface build from repository metadata.

## Setup

1. Install this branch for two Retail clients with distinct accounts/characters in the same raid.
2. On each client, run `/dump select(4, GetBuildInfo())`; record the returned interface and compare it with `## Interface: 120105`.
3. Make client A raid leader. Keep client B a normal raid member. Add a third raid member without the addon if available.
4. Reload both addon-equipped clients and confirm there are no Lua errors or duplicate event reactions.

## Leader and participant path

1. On client A, run `/syb status`, then `/syb devnetstart`. Confirm discovery is only queued, not reported as delivered.
2. On client B, run `/syb status`. Confirm the detected leader is client A and the session ID/version are shown without ballot data.
3. Exchange HELLO and one sanctioned role command. Confirm client B remains pending until an authoritative ACK is received, then reports the new confirmed version.
4. Retry the identical command ID and confirm it is not applied twice.
5. Confirm silence remains unknown and blocks Start after the discovery timeout. Through the live-GUID confirmation seam, confirm a genuinely no-addon member becomes passive and no longer blocks, while a detected addon user awaiting role remains pending and does block it.
6. Add a raid member after session start and confirm the member is projected as a late-joiner observer.

## Rejection and recovery path

1. Have client B attempt an admin action. Confirm `not_raid_leader` and no state mutation.
2. Send a malformed, oversized, stale-session, stale-version, and unknown command from a test build. Confirm each fails closed with a diagnostic.
3. Remove a sender from the raid and confirm subsequent messages are rejected as `sender_not_in_raid`.
4. Disconnect a participant and confirm the explicit disconnected projection/event.
5. Transfer raid leadership from client A. Confirm the session pauses and then ends with `authority_changed`; it must not promote the new leader into the old session.
6. Inspect addon-message traffic and participant UI/chat. Confirm no voter-to-rating or identifiable ballot detail is broadcast.

Record client builds, accounts/roles used, exact observed results, and any Lua errors in the pull request. Keep every unexecuted item marked **Not run**.
