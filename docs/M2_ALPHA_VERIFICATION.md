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


## First live registration test and Preparation checkpoint

Doug reported that the leader opened registration and six raid members were present in total. Other players could join and select their roles; no tester reported a Lua error. The leader reported Start was disabled. This supports registration working in the live raid, not a live pass for Start. No contemporaneous readiness diagnostic was captured, so the reason for the original disabled button is unknown.

The follow-up keeps the current readiness explanation separate from old action notices and adds a dedicated Preparation view. The mocked Retail suite now verifies one leader and exactly five contestants, verifies that fewer than five cannot start, and asserts that each client reaches Preparation with the correct role. The existing larger fixture still exercises the spectator, no-addon observer and reconnect cases. The protocol and eligibility rules were not changed.

At the next planned raid test, use the same ZIP on all addon clients. With one leader and five confirmed contestants, let discovery complete. If Start stays grey, capture its on-screen explanation and the `lobby:` value from `/syb status` before closing the lobby. If Start works, all six clients should show **Round 1 of 1: Preparation**. On slower clients, allow up to 25 seconds for the next sync or use **Refresh**. No separate raid session is required just to recheck this.

### Next slice: M3 contest execution

- Build the approved theme reveal and synchronized preparation timer (UX-05; EP-05/06). Include a clear end-of-preparation state controlled by the raid leader, and keep future-round themes hidden.
- Next, move from preparation into a randomized runway with leader-controlled advance (UX-06/20; EP-07). Verify that the last presentation hands off to voting.
- Implement 1–5-star voting and round progression after the runway. The configuration wizard, results and full disconnect recovery are still outstanding.

This checkpoint does not implement theme selection/reveal, the countdown, or any gameplay after Preparation. It is not a playable contest release.
