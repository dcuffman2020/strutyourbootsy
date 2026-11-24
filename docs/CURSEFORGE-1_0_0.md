# Strut Your Bootsy 1.0.0 release checklist

- Existing [CurseForge project](https://authors.curseforge.com/#/projects/1823004/files); add a new file without changing the previous beta.
- Project ID: 1823004. File type: **Release**. Display name: **Strut Your Bootsy 1.0.0**.
- Game version: **WoW Retail 12.1.5**, TOC interface `120105`. No required addon dependencies.
- Upload `StrutYourBootsy-1.0.0.zip`. The ZIP has one root folder, `StrutYourBootsy/`, containing `StrutYourBootsy.toc`, Lua runtime files, and textures. Do not rezip using Finder.
- Use the version section from [CHANGELOG.md](../CHANGELOG.md). Configure automatic publication after approval.
- Keep the footer credited to CraftyMonkeyButter. A build assembled before moderation has a build date, not a guessed publication date. Record the date actually reported by CurseForge after approval.
- Verify the exact file, release classification, and game version in the author dashboard. Treat Uploading or Under Review as not publicly available. Report a public download link only after verification.

## Targeted post-build smoke

1. With matching clients, use `/syb` and verify the minimap icon, Help, and Practice launcher still respond. Verify the footer reads 1.0.0 and has the correct credit.
2. Host a two-round Solo contest with five contestants and at least one spectator. Verify each round prepares, presents, votes, and aggregates independently. Check partial ballots, duplicate rejection, and that the raid leader cannot vote.
3. Host a two-round Team contest with three complete teams. Verify leadership handoff, team-level scores, and that voters cannot rate their own team. Disconnect/reconnect a contestant and compare their phase, round, and eligible ballot after resync.
4. Compare the final standings across ready clients; verify ties and the leader-controlled reveal. Outfit models still depend on which appearance data WoW exposes. A full logout or interface reload of the original host is not a supported recovery path; do not confuse that with a contestant reconnect.
