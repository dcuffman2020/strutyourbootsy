# Strut Your Bootsy | Tournament Armory practice alpha

This is a private test build. Live raid play still ends at the runway. Solo practice can configure rounds, pause/resume, cast a sample ballot, and review results. No practice actions affect your raid.

## Install

1. Fully exit WoW Retail. Extract the ZIP and copy the single `StrutYourBootsy` folder to `_retail_/Interface/AddOns/`. Keep the entire included `Assets` folder. Do not put the addon inside a second nested `StrutYourBootsy` directory.
2. Enable the addon at character select. Use the Bootsy minimap button or type `/syb`. The minimap button drags to a new position.

Click the **?** bubble in the addon header for quick instructions on hosting, joining, solo practice, and troubleshooting. **Got it** returns you to the same screen.

## Personalize the addon

Open **Options → Appearance**. Select **Tournament Armory**, **Goldleaf Grimoire**, **Studio Modern**, **Neon Circuit**, or **Snowglow Lodge** to preview it immediately on the live window. The swatches identify each look; the checkmark shows what you are previewing. **Apply theme** saves this character’s appearance and returns to Options. **Cancel** or closing the window discards an unapplied preview. Appearance is client-only and separate from the contest theme. High contrast and other interface settings still work with every skin.

## Watch the runway without the full window

Click the **minus** under the close button to collapse the addon to a small bar. The contest continues and the bar shows who is presenting. Click **Restore**, the minimap icon, or type **/syb** to reopen the current screen. Drag the full window by its header or the small bar by its left side. Native dragging is independent of BlizzMove and only touches this addon’s two windows. If you prefer to manage movement with an external addon, set **Options → Window dragging** to **Off**, then save. Window and bar positions are independent within the current game session.

## Test solo (no group needed)

1. While outside a party or raid, type **`/syb practice`**. The window is marked **Practice mode**, with five fictional contestants ready in the lobby.
2. Click **Start contest**. Confirm the theme and timer appear. Wait for expiry to test the actual clock, or use the practice-only **Skip countdown**.
3. Click **Begin runway**. The turn clock starts at 2:00 by default, separate from prep, and restarts on **Next contestant**. Verify all five names are visible to the host. Time running out does not advance; use **Next contestant** and finally **Finish runway**.
4. On **Runway complete**, choose **Begin voting**. Rate any of the other fictional contestants and submit. A submitted ballot cannot be edited. Wait for the vote timer or use **Skip vote timer**, then **View round results**.
5. Round results highlight first, second, and third in gold, silver, and bronze. Equal scores share the same place and color. Follow the result screen to the next round or **Final awards**, where each medal color appears as its winner is revealed. **Practice again** restarts the walkthrough. **Exit practice** (also `/syb practice stop`) returns to normal. Practice shows a local warning banner, plays the raid warning sound when game audio is enabled, logs the warning in your own chat, sends no raid traffic, and exits when you join a group.
6. In the lobby, **Theme...** opens a text editor. **Use theme** saves the typed name for this contest; **Random theme** returns to automatic selection. The name stays hidden from contestants until **Start contest**. **Runway timer** sets the per-turn duration before starting.
7. In **Setup Contest**, the highlighted round updates the summary. The selected custom theme appears first above the preset options. Click the highlighted row or **Edit theme** to change the name.
8. Choose **View as** in the practice header and pick a fictional contestant. This read-only view shows their side of the current phase, with the same timer and current/next turns but no host controls. **Host view** returns you without changing the contest. Try switching views before and after the reveal.
9. Preview the contestant who is presenting and open **Emotes +**. The top row is always **Bow**, **Wave**, **Dance**, **Flex**, and **Chicken**. The other 15 slots are sampled from the runway emote pool without repeats. Close and reopen the panel during the same turn to verify the choices stay put; a new turn loads a fresh draw. Practice shows feedback but does not perform a game emote. A contestant who is merely up next should not see the picker. After a selection, all emote buttons pause for two seconds in both practice and live play. Extra clicks are ignored, not queued; closing or minimizing does not bypass the pause.

## Contestant portraits

Contestants see their own face portrait marked **YOU**. Registered contestant rows and the host’s runway order show face portraits where WoW can render the raid unit. If a player is unavailable or not in view, the portrait tile shows an initial instead. Fictional practice contestants always use initials. This is display-only; it does not target or inspect anyone.

## Next group test

Use this same version on the raid leader and five confirmed contestants. Schema 4 does not mix with earlier builds. Open registration, wait for discovery, confirm all five, and click **Start contest**. Everyone should see the same theme and finish time. At expiry only the leader can begin and advance. The leader sees the full order; participants see the current and next contestant. Verify one consistent progression across all clients through **Runway complete**. During a live contestant’s turn, verify that one deliberate click performs one game emote and the picker vanishes after the leader advances. The current emote hook is covered by mocked client tests; confirm actual animation and layout in Retail. If a client misses an update, use **Refresh** to catch up. If Start is disabled, capture the reason or the `lobby:` value from `/syb status`.

## Raid Warnings

This is a change from the PRD’s ordinary raid-chat channel. The live host sends one Raid Warning when registration opens or is cancelled, preparation opens (with the revealed theme), each contestant starts presenting, and the runway ends. The first contestant’s warning also announces that the runway has begun. Timer ticks, reconnects, and UI refreshes are silent. Practice previews these with a banner marked [Practice] and the game’s raid warning sound. It also previews voting opening and closing, round leaders, and the final congratulations after the last podium reveal.

Live ballots and scoring are still out of scope for this alpha. After the live runway ends, the raid leader can announce an externally determined podium once with `/syb announce winners First Second Third`. Enter the three actual contestant names in finish order, with `-Realm` for ambiguous names. Only names from the completed runway are accepted. The warning reads “Congratulations to First Second Third!” Check the feature with an opted-in test raid; automated tests use mock chat, not the Retail client.

If a registered contestant disconnects, current alpha controls hold until they return. Full recovery is a separate milestone. If testing a second *live* contest, reload the group clients for a fresh test session. Do not send SavedVariables or account details with an error report.

## Build information

The lower-right footer reads the version, publication date, and creator credit from the addon manifest. For each alpha you package, update both `Version` and `X-Published-Date` in `StrutYourBootsy.toc`. The display date is the release date, not the date the player installed it.
