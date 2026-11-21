# Strut Your Bootsy | Theme and preparation checkpoint

This is a private test build, not a playable contest. It verifies lobby readiness, theme reveal, and the two-minute countdown for one round. The full theme catalog, setup wizard, runway, and voting are not included.

## Install

1. Fully exit WoW Retail. Extract the ZIP and copy the one `StrutYourBootsy` folder into `_retail_/Interface/AddOns/`. Keep the included `Assets/BootsyMinimap.tga` file in the addon folder. The manifest must be at `_retail_/Interface/AddOns/StrutYourBootsy/StrutYourBootsy.toc`, without a second nested addon folder.
2. Enable Strut Your Bootsy on the character screen. In game, use `/syb` to open the window. `/syb status` prints diagnostics. The Bootsy head icon opens the same window; drag it to reposition. No account credentials or additional installer are needed.

## At the next scheduled raid test

1. Install this same build on all six players. The earlier registration build cannot join this version. Use one raid leader and five contestants. The leader opens registration from `/syb`. Each of the other five selects and confirms **Contestant**. Let discovery finish.
2. When **Start contest** enables, click it once. All six should see **Round 1 of 1: Preparation**, the same theme, and a countdown to the same end time. The theme should not be visible before Start. Most clients should update immediately; if a client misses the initial reveal, use **Refresh** and confirm its timer joins the others, not a fresh two minutes.
3. Let the timer expire. All clients should see **Preparation complete**. No runway starts in this build.
4. If Start stays disabled, capture the readiness text above it and the `lobby:` value from `/syb status` before closing the lobby. No need to organize a separate raid for this checkpoint.

If the addon does not load, check the folder nesting. If an error appears, share the error message only, not your SavedVariables or account details. This package declares Retail interface `120105`. Do not delete other addons or the `WTF` directory.
