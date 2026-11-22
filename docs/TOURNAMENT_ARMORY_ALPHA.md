# Tournament Armory: interactive alpha checkpoint

Visual references: [Tournament Armory design](https://www.figma.com/design/c2Qaeb9hHOcYtdtPXAi8Vl/Strut-Your-Bootsy-UX?node-id=43-64), [runway](https://www.figma.com/design/c2Qaeb9hHOcYtdtPXAi8Vl/Strut-Your-Bootsy-UX?node-id=44-268), [ballot](https://www.figma.com/design/c2Qaeb9hHOcYtdtPXAi8Vl/Strut-Your-Bootsy-UX?node-id=44-1066).

The 465-unit native Lua window uses the approved burgundy titlebar, small Bootsy mark, iron panels, gold trim, visible phase tracker, and centered actions. The close, divider and two star textures are native-size renderings of the Figma assets, not screenshots of screens. Bootsy reuses the same approved image from the minimap. The native client font substitutes for the non-bundled Figma fonts.

## Implemented and wired

- **Live and practice:** Welcome launcher, lobby, preparation, runway, and completion use the new skin. Live retains role selection and confirmed observer handling. Start and host actions are gated by the existing raid authority and readiness checks. The protocol is unchanged from the prior schema-3 alpha; this branch does not introduce live ballots.
- **Solo practice:** Setup is an optional five-step flow with a cancellable draft, 1–5 rounds, a small local practice theme pool, preparation/voting durations, and review. The default slash command still opens directly to the ready fictional lobby. Skip timers act only on the practice controller.
- **Solo runway through results:** Pause/resume preserves the current turn. The last turn opens a timed local ballot as fictional Cinderstep; self-rating is unavailable, partial ballots are allowed, and submission locks edits. Results only show aggregate scores. Rounds repeat if configured. The podium is revealed in reverse order, with fourth place eligible for Honorable Mention. A tie affecting the podium blocks awarding until a tie-break flow exists. A single practice ballot is illustrative, not real raid voting.
- **Options:** Per-character size preview and save, contrast, reduced motion for the subtle urgent clock cue, and optional sounds. Cancel returns to saved values. Clicking Reset previews defaults until Save.

## Remaining, not represented as working

Live configuration, ballots and round/results transport, live pause and recovery states, tie-breaking controls, participant removal, and the full theme catalog remain separate slices. No portraits or emotes added. This is not a port of every one of the 35 design states. The separate Figma originals remain untouched.

## Validation

Lua 5.1 and 5.4 tested with the actual TOC order and mocked WoW frames. Coverage includes setup cancel/review, saved contrast, two complete practice rounds, pause/resume, reference assets, inability to rate oneself, locked ballot, results/awards, exit, and zero network packets. Existing six-client registration, preparation and runway flow also ran. Native Retail appearance and the new buttons still need an in-game check; headless testing is not visual or network acceptance.
