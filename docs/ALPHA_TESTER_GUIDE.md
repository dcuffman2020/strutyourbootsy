# Strut Your Bootsy | Preparation checkpoint

This is a private test build, not a playable contest. It verifies lobby readiness and the handoff into Preparation. It does not include the theme reveal, timer, runway, or voting.

## Install

1. Fully exit WoW Retail. Extract the ZIP and copy the one `StrutYourBootsy` folder into `_retail_/Interface/AddOns/`. The manifest must be at `_retail_/Interface/AddOns/StrutYourBootsy/StrutYourBootsy.toc`, without a second nested addon folder.
2. Enable Strut Your Bootsy on the character screen. In game, use `/syb` to open the window. `/syb status` prints diagnostics. No account credentials or additional installer are needed.

## At the next scheduled raid test

1. Install the same build on all six players: one raid leader and five contestants. The leader opens registration from `/syb`. Each of the other five selects and confirms **Contestant**. Let discovery finish.
2. When **Start contest** enables, click it once. The leader and all five contestants should see **Round 1 of 1: Preparation** after syncing. Allow up to 25 seconds or use **Refresh** if needed.
3. If Start stays disabled, capture the readiness text above it and the `lobby:` value from `/syb status` before closing the lobby. No need to organize a separate raid for this checkpoint.

If the addon does not load, check the folder nesting. If an error appears, share the error message only, not your SavedVariables or account details. This package declares Retail interface `120105`. Do not delete other addons or the `WTF` directory.
