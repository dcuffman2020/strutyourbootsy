# Strut Your Bootsy: Team contest specification

**Status:** Product rules approved for implementation, November 22, 2026. Design reference: [Team Mode Concepts in Stitch](https://stitch.google.com/projects/225987967489115702). This is an addendum to the MVP 2.1 requirements baseline (November 8, 2026) and extends, rather than replaces, the [Solo UX and engineering contract](UX_ENGINEERING_CONTRACT.md).

## Contest format and readiness

- The raid leader selects **Solo** or **Team** before opening registration. Solo is the default and retains its five-contestant minimum. A contest cannot mix solo entries with team entries. In Team mode the raid leader selects one size for all teams: **2, 3, 4, or 5 contestants**. Format and size are fixed once registration opens.
- Team Start requires **at least three complete teams** (6, 9, 12, or 15 contestants, respectively). The host lobby shows the number of complete teams, each roster’s occupancy, and unassigned contestants. Ordinary registration eligibility, connected roster and pending-role checks still apply. An unassigned contestant must join a complete team or switch to Spectator; a partial team is not eligible to enter the runway.
- A player may belong to only one team. A team must not exceed the selected size. At Start, lock rosters, names, and leadership for the contest. A pending nomination does not transfer leadership after the lock.

## Roles and team leadership

| Role | Can do | Cannot do |
|---|---|---|
| **Raid leader** | Set the contest format and team size, open registration, check readiness, start and advance the contest | Compete or vote, name or rename a team, or appoint a Team leader |
| **Team leader** | Name or rename their own team in the lobby; nominate another confirmed member of that same team when it has at least two members | Rename another team, transfer leadership unilaterally, or gain raid controls |
| **Contestant** | Create or join a team; accept or decline a nomination addressed to them | Rename a team or nominate someone unless they currently lead that team; rate their own team |
| **Spectator** | Watch and rate any team when voting opens | Join, name, or lead a team as a spectator |

The contestant who successfully creates the team supplies its initial name and automatically becomes its **Team leader**. Only the current Team leader can send a nomination. Sending it does not change any permissions: the nominee must explicitly accept. On acceptance, transfer leadership and naming rights together, retain the existing team name and roster, and revoke the former leader’s naming and nomination rights. On decline, the existing leader and team name stay unchanged. Do not transfer in response to someone other than the nominee, a stale nomination, a player leaving the team, or the registration phase ending. The raid leader does not participate in a leadership transfer.

## Screen flow

1. **Contest format (raid leader):** mutually exclusive Solo and Team choices. Show the team-size selector only for Team. State the minimum and when the choices lock; open registration with the selected format.
2. **Find a team (contestant):** automatically follow confirmed Contestant registration in an open Team lobby if the player has no team. Show each team’s name, players and occupancy; enable Join only for eligible open teams. Show Create team even when no teams exist, and a route to switch to Spectator. Solo contestants and spectators skip this screen.
3. **Your team:** display the named roster and a text label identifying the Team leader. After creating or joining, show the authoritative roster. Only the Team leader sees controls to edit that team’s name or nominate an eligible teammate. Nomination identifies the teammate and explains that acceptance is required.
4. **Leadership nomination (nominee):** identify who nominated the player and for which team. Offer **Accept nomination** and **Decline**. Until the host acknowledges acceptance, do not render the nominee as leader or enable naming controls.
5. **Team details (new leader):** on accepted transfer, show the updated leader badge, retain the existing name, and offer an editable Team name field. Team members and the raid leader otherwise see the name as read-only.

## Runway, voting, and results

- Each team presents together in one shared runway turn. Display the team name, members, and its position in the lineup. Completed teams’ available outfit previews can be browsed one member at a time using the gallery; previews do not affect eligibility or scoring.
- A ballot records one **1–5 star rating per team** the voter chooses to rate, rather than per member. Contestants cannot rate their own team, spectators can rate any eligible team, and the raid leader has no ballot. Existing ballot finality, rating deadline, and aggregate-only results apply. Team results identify the team as the scored entry.
- Practice can demonstrate the workflow with three fictional duos and must not require a real raid or send raid traffic.

## Implementation and acceptance notes

- Check format, phase, identity, membership, team capacity, nomination validity, and voting eligibility on the authoritative raid-leader client, not just in the UI. Treat the host’s protocol authority as separate from the raid leader’s player permissions. Repeated join, nomination, acceptance, and ballot requests must not create duplicate mutations.
- Verify 2-, 3-, 4-, and 5-player readiness, three-team minimum, unassigned and disconnected contestants, simultaneous attempts at the last slot, leader-only naming and nomination, decline, successful transfer and old permissions revocation, stale acceptance, mixed-entry rejection, and both contestant and spectator ballots. Regression-test Solo, including the five-player minimum and self-vote protection.
- Team name validation, layout details, and whether a sole remaining roster is disbanded or retained are implementation choices, not separate approved product rules. Treat team departure, disconnect, and leadership recovery without a valid nomination carefully; never silently award the raid leader team-naming privileges. Simulated raid coverage does not establish that the flow works on live Retail clients.

### Alpha delivery notes

- Team mode uses one live round and the existing 60-second live ballot. The current Team leader must transfer leadership before voluntarily leaving a nonempty team. Disconnect handling is still the existing alpha policy; the raid leader does not receive naming or promotion permissions.
- The offline shortcut `/syb teampractice` starts a preassembled three-duo example with a sample spectator ballot. Use a simulated or real raid to exercise formation and leadership transfers. The practice tally is illustrative; live qualification still requires at least two ratings.
- All raid clients must use the same Team-capable build (protocol schema 8). Full-body Preview may fall back to the member’s name/face. Use the next planned Retail test to verify actual client rendering and packet delivery.
