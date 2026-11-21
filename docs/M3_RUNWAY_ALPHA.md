# M3: Runway and solo practice

The one-round runway uses the existing Core state machine. At successful Start the host freezes and independently shuffles the confirmed roster. Only the original raid leader can begin (at or after the preparation deadline), advance one turn, or finish the last turn. The next state is explicitly `runway_complete`; an early Core voting transition is rejected. Voting is not exposed in the client.

Schema 3 distributes versioned turn state (position, total, current and next GUID) with bounded raid announcements and existing WELCOME refresh recovery. Raw player names are not sent as separate fields. The leader has the full order and holds advancement if any frozen contestant is unavailable. Full pause/recovery and round progression are not implemented.

`/syb practice` is a different in-memory controller with five fictional contestants, using the same Core functions, screens, and buttons. It cannot open in a party or raid; group membership ends practice. It has an optional local skip-the-countdown button, restart, and exit. No practice action goes through raid transport.

Tests: Lua 5.1 and 5.4 cover the prep gate, unique turns, leader-only controls, disconnect hold, missed update recovery, matching completion on six simulated clients, and the full solo loop with zero addon messages. Retail rendering and native multi-client behavior are still unverified. Use the [tester guide](ALPHA_TESTER_GUIDE.md).
