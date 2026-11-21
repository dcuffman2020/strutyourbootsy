# M3 alpha: Theme reveal and synchronized preparation

This one-round slice follows the Preparation handoff and implements UX-05 / EP-05 and EP-06. The raid leader's successful Start draws one provisional theme from a small alpha pool, exposes it to all eligible clients (late observers get read-only status), and sets one 120-second deadline from WoW server time. There are no theme fields in discovery or registration. Full theme catalog, custom themes and multi-round configuration remain separate work.

The leader sends a single authenticated raid state update for this phase. Clients validate the leader, current session, version, and reveal fields before rendering the update. Existing staggered refresh and leader replies recover a missed reveal with the same deadline. The retry uses the existing send budget. A delayed reply never starts a new client timer. This build uses protocol schema 2; install the same ZIP on all alpha clients. It is intentionally not interoperable with the prior registration alpha.

The countdown uses the shared deadline, not client arrival time. At expiry the UI shows Preparation complete, without automatically entering a phase this build does not implement. Next: leader-authorized transition to runway, randomized order, and advancing one contestant at a time. Voting and full disconnect recovery are not part of this checkpoint.

## Verification

Run `for test in tests/*_spec.lua; do lua "$test" || exit; done` on Lua 5.1 and 5.4. Coverage includes the exact six-player simulated roster, no theme leakage before Start, same theme and countdown across clients, packet loss and refresh, late-join observer view, and transition to the expired state. The network spec rejects invalid reveal data, stale versions and messages from the wrong sender or session.

See [the tester guide](ALPHA_TESTER_GUIDE.md) for the live Retail acceptance gate. Headless tests do not establish actual WoW transport, timing, or visual behavior.
