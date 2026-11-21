# M1 and M2 alpha verification

The Retail client installed for this review reports 12.1.5.70961. The addon declares interface 120105 and loads `Core.lua`, `Network.lua`, `UI.lua`, and `Main.lua` in that order.

## Automated coverage

The Core, Network, and registration specs pass on Lua 5.1.5 and 5.4.8. Run them from the repository root with `for test in tests/*_spec.lua; do lua "$test" || exit; done`.

The registration spec loads the actual TOC in isolated clients with mocked WoW APIs. It covers solo slash commands, prefix registration failure and retry, minimap click and drag callbacks, the Escape frame registration, discovery, role confirmation, rejected transport, pending roles, passive observer confirmation, duplicate command replay, disconnected contestants, late joins, and the authoritative transition into preparation. The Network spec additionally checks stale sessions and versions, rejected non-leader Start, GUID-bound authority, replay handling, payload bounds, and leadership transfer.

The raid leader can open a one-round alpha registration session without the configuration wizard. Start supplies a deterministic name-ordered list to Core for this slice. Random runway order and subsequent gameplay screens remain future work. Client whispers carry the current phase and that recipient's registration, with no ballot fields. Convergence uses staggered polling and command acknowledgments. Conflicting role submissions may require refreshing and confirming again.

## Retail smoke test

1. Extract the ZIP so the TOC sits at `_retail_/Interface/AddOns/StrutYourBootsy/StrutYourBootsy.toc`. Enable Lua errors with `/console scriptErrors 1` and reload. Confirm the interface with `/dump select(4, GetBuildInfo())`.
2. While solo, run `/syb` twice. Reopen and test Escape, the close button, and dragging. Click and drag the minimap launcher. Verify its placement persists after reload and adjacent Blizzard controls remain clickable.
3. Form a raid with the same build on the leader, five contestants, and one spectator. Include a member without the addon. The leader opens registration and the addon-equipped players confirm their roles. Leave the spectator pending and verify Start stays disabled even after five contestants register.
4. Confirm the spectator. The leader checks with the no-addon player, selects their unconfirmed roster row, and clicks **Confirm no addon** after discovery. Verify that an addon-equipped pending member cannot be classified as passive.
5. Add a late joiner. Check their observer state. Disconnect one of the registered contestants and verify Start disables, then reconnect them and verify readiness recovers. Verify the leader has no role controls and the other clients have no Start control.
6. Start the contest. Wait for each client's next refresh and verify that registration closes on all addon clients. In a fresh raid registration, transfer raid leadership and verify the previous registration ends. Repeat with cross-realm characters.

Real-client validation is pending for Escape handling, UI scale and minimap overlap, Retail chat delivery and throttling, roster ordering during reconnects and transfers, and visual acceptance against UX-03 and UX-04. Full post-start disconnect recovery is outside this registration slice.
