# Strut Your Bootsy — Developer Alpha / Multiplayer Smoke Test

**Experimental test build, not a functional transmog contest.** Free, unofficial community addon. Do not use during important group content. No sensitive credentials, Codex, GitHub account, or other software is required for testers.

## Quick install (Windows and macOS)
1. Fully exit World of Warcraft Retail.
2. Extract the ZIP. Inside, find the folder **StrutYourBootsy** containing `StrutYourBootsy.toc`, `Core.lua`, `Network.lua`, `Main.lua` and this guide.
3. Copy **StrutYourBootsy** into `World of Warcraft/_retail_/Interface/AddOns/`. Do not add an extra nested StrutYourBootsy folder. The resulting file is `_retail_/Interface/AddOns/StrutYourBootsy/StrutYourBootsy.toc`.
4. Start Retail. At character select, use **AddOns** to verify **Strut Your Bootsy** is enabled. Check that it is not labeled incompatible/out of date.
5. Log in and type `/syb status`. If you see an error, take a screenshot and share it with the organizer. You should not be asked to provide credentials or other personal data.

## Test session
1. Join a **raid group** with the organizer. The organizer must be the raid leader. Two members are enough for a communication smoke test; you are not running the five-contestant contest.
2. With both clients logged in and the addon enabled, run `/syb status`.
3. The organizer (and ONLY the raid leader) runs `/syb devnetstart`. This starts developer-only addon discovery; it is not the final contest.
4. After discovery, run `/syb status` again and report the chat output. Look for a session identifier and version on the participant client, and avoid posting any account-identifying details in public channels.
5. Organizer collects success/error screenshots and notes. No UI, transmog judging, or gameplay automation is expected yet.

## Troubleshooting
- If commands are absent, confirm folder nesting and addon enabled state, then `/reload`.
- If an error appears, enable Lua script error reporting with `/console scriptErrors 1` followed by `/reload`. Share the **error message**, not saved variables or account details. After testing you may restore `/console scriptErrors 0`.
- The organizer should record WoW client interface: `/dump select(4, GetBuildInfo())`. The package declares interface `120105`; report a mismatch.
- Do not delete other addons or the `WTF` directory to troubleshoot.
- Uninstall by fully exiting WoW and removing only `_retail_/Interface/AddOns/StrutYourBootsy`.

## Known limitations
- No playable contest UI, real runway, voting, scores, or complete recovery behavior.
- This test mainly verifies addon loading, HELLO/WELCOME discovery, and leader-authoritative multiplayer infrastructure.
- No manual client-side role command is exposed in this build; authenticated ROLE messaging is covered in automated tests, not via a tester UI.
- Some status/absence cases will show `insufficient_contestants` during this two-client check; that is expected.
- The game addon uses only its WoW sandbox and does not need external apps or installers.

Source and version: https://github.com/dcuffman2020/strutyourbootsy/pull/4 . This test package is generated only from reviewed repository Lua/TOC files, plus this guide.
