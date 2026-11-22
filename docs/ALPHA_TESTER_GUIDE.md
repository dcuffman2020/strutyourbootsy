# Strut Your Bootsy | Tournament Armory practice alpha

This is a private test build. Live raid play still ends at the runway. Solo practice can configure rounds, pause/resume, cast a sample ballot, and review results. No practice actions affect your raid.

## Install

1. Fully exit WoW Retail. Extract the ZIP and copy the single `StrutYourBootsy` folder to `_retail_/Interface/AddOns/`. Keep the entire included `Assets` folder. Do not put the addon inside a second nested `StrutYourBootsy` directory.
2. Enable the addon at character select. Use the Bootsy minimap button or type `/syb`. The minimap button drags to a new position.

## Test solo (no group needed)

1. While outside a party or raid, type **`/syb practice`**. The window is marked **Practice mode**, with five fictional contestants ready in the lobby.
2. Click **Start contest**. Confirm the theme and timer appear. Wait for expiry to test the actual clock, or use the practice-only **Skip countdown**.
3. Click **Begin runway**. Verify that all five names are visible and that **Presenting** and **Up next** update. Use **Next contestant** for the first four turns, then **Finish runway**.
4. On **Runway complete**, choose **Begin voting**. Rate any of the other fictional contestants and submit. A submitted ballot cannot be edited. Wait for the vote timer or use **Skip vote timer**, then **View round results**.
5. Follow the result screen to the next round or **Final awards**. **Practice again** restarts the walkthrough. **Exit practice** (also `/syb practice stop`) returns to normal. Practice sends no raid traffic and exits when you join a group.
6. Try **Setup** in the practice lobby and **Options** in the header. Start with default settings if you only want to check the new design.

## Next group test

Use this same version on the raid leader and five confirmed contestants. It does not mix with earlier builds. Open registration, wait for discovery, confirm all five, and click **Start contest**. Everyone should see the same theme and finish time. At expiry only the leader can begin and advance. The leader sees the full order; participants see the current and next contestant. Verify one consistent progression across all clients through **Runway complete**. If a client misses an update, use **Refresh** to catch up. If Start is disabled, capture the reason or the `lobby:` value from `/syb status`.

If a registered contestant disconnects, current alpha controls hold until they return. Full recovery is a separate milestone. If testing a second *live* contest, reload the group clients for a fresh test session. Do not send SavedVariables or account details with an error report.
