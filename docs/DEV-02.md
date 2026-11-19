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
