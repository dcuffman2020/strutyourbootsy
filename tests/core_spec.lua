-- Run with a standalone Lua interpreter from the repo root:
--   lua tests/core_spec.lua
local namespace = {}
local loader = assert(loadfile("Core.lua"))
loader("StrutYourBootsy", namespace)
local Core = assert(namespace.Core)
local function fails(ok, reason)
    assert(ok == false and type(reason) == "string", "expected rejection")
end
local s = Core.New("Admin-Realm", 2)
for i = 1, 5 do assert(Core.Register(s, "Player" .. i, "contestant")) end
assert(Core.Register(s, "Viewer", "spectator"))
fails(Core.Register(s, "Admin-Realm", "contestant"))
fails(Core.Register(s, "Player1", "spectator"))
fails(Core.CanStart(s, 1))
assert(Core.CanStart(s, 0))
local order = {"Player1", "Player2", "Player3", "Player4", "Player5"}
local shuffled = Core.Shuffle(order, function() return 0 end)
assert(table.concat(shuffled,",") == "Player2,Player3,Player4,Player5,Player1")
assert(order[1] == "Player1")
assert(Core.Start(s, order, 0))
assert(Core.BeginRunway(s))
fails(Core.BeginVoting(s))
for i = 1, #order do
    local r = Core.RunwayStatus(s)
    assert(r.index == i and r.current == order[i] and r.upcoming == order[i+1])
    assert(Core.AdvanceRunway(s))
end
assert(s.phase == "runway_complete" and not Core.RunwayStatus(s).current)
fails(Core.AdvanceRunway(s))
assert(Core.BeginVoting(s))
fails(Core.SubmitBallot(s, "Player1", { Player1 = 5 }))
fails(Core.SubmitBallot(s, "Admin-Realm", { Player2 = 5 }))
fails(Core.SubmitBallot(s, "Viewer", { Player2 = 6 }))
assert(Core.SubmitBallot(s, "Viewer", { Player1 = 5, Player2 = 4, Player3 = 3, Player4 = 2, Player5 = 1 }))
fails(Core.SubmitBallot(s, "Viewer", { Player1 = 1 }))
assert(Core.CloseVoting(s))
assert(s.scores[1].Player1 == 5)
assert(Core.NextRound(s))
assert(Core.BeginRunway(s))
fails(Core.BeginVoting(s))
for i = 1, #order do
    local r = Core.RunwayStatus(s)
    assert(r.index == i and r.current == order[i] and r.upcoming == order[i+1])
    assert(Core.AdvanceRunway(s))
end
assert(s.phase == "runway_complete" and not Core.RunwayStatus(s).current)
fails(Core.AdvanceRunway(s))
assert(Core.BeginVoting(s))
assert(Core.SubmitBallot(s, "Viewer", { Player1 = 4, Player2 = 5, Player3 = 3, Player4 = 2 }))
assert(Core.CloseVoting(s))
local results = assert(Core.FinalResults(s))
assert(#results == 4) -- Player5 did not receive a second-round rating.
assert(results[1].name == "Player1" or results[1].name == "Player2")
assert(results[1].average == 4.5)
assert(Core.Pause(s))
assert(Core.Resume(s))
assert(Core.End(s))
-- Configuration boundary and podium workflow on real round-generated scores.
for n=1,5 do assert(Core.ValidRounds(n)) end
for _,n in ipairs({0,6,-1,1.5,"2",false,math.huge}) do assert(not Core.ValidRounds(n)) end
assert(Core.New("Admin").rounds==1)
assert(not pcall(Core.New,"Admin",0))

local function qualified(rounds, ballots)
    local c=Core.New("Host",rounds)
    for _,name in ipairs(order) do assert(Core.Register(c,name,"contestant")) end
    assert(Core.Start(c,order,0))
    for r=1,rounds do
        assert(Core.BeginRunway(c))
        for _ in ipairs(order) do assert(Core.AdvanceRunway(c)) end
        assert(Core.BeginVoting(c))
        for voter,ratings in ipairs(ballots[r]) do assert(Core.SubmitBallot(c,"Viewer"..voter,ratings)) end
        assert(Core.CloseVoting(c,2))
        if r<rounds then
            local early,why=Core.OpenAwards(c)
            assert(not early and why=="not_finished")
            assert(Core.NextRound(c))
        end
    end
    return c
end

-- Unequal ballot counts between rounds do not weight one round more. Third
-- and fourth tie across the podium line; fifth lacks enough second-round votes.
local tie=qualified(2,{
    {{Player1=5,Player2=4,Player3=3,Player4=3,Player5=1},
     {Player1=5,Player2=4,Player3=3,Player4=3,Player5=1},
     {Player1=5,Player2=4}},
    {{Player1=3,Player2=3,Player3=3,Player4=3,Player5=5},
     {Player1=3,Player2=3,Player3=3,Player4=3}}
})
local cumulative=Core.Cumulative(tie)
assert(cumulative.Player1==4 and cumulative.Player2==3.5 and not cumulative.Player5)
local over,why=Core.NextRound(tie); assert(not over and why=="final_round")
assert(Core.OpenAwards(tie))
assert(#tie.awards.results==4 and tie.awards.ties.Player3==3 and tie.awards.ties.Player4==3)
fails(Core.RevealAward(tie))
local confirmed,reason=Core.ConfirmAwards(tie); assert(not confirmed and reason=="rolls_required")
for _,bad in ipairs({0,101,9.5,"90"}) do fails(Core.RecordRoll(tie,"Player3",bad)) end
fails(Core.RecordRoll(tie,"Player1",100))
assert(Core.RecordRoll(tie,"Player3",90) and Core.RecordRoll(tie,"Player4",90))
confirmed,reason=Core.ConfirmAwards(tie)
assert(not confirmed and reason=="reroll_required" and next(tie.awards.rolls)==nil)
assert(Core.RecordRoll(tie,"Player3",10) and Core.RecordRoll(tie,"Player4",90))
assert(Core.ConfirmAwards(tie))
assert(tie.awards.results[3].name=="Player4" and tie.awards.results[4].name=="Player3")
fails(Core.RecordRoll(tie,"Player4",1))
for i=1,3 do assert(Core.RevealAward(tie) and tie.awards.revealed==i) end
fails(Core.RevealAward(tie))

-- Ties entirely outside the podium require no roll; no-result contests
-- can confirm without a reveal, and this applies to one-round contests too.
local one=qualified(1,{
    {{Player1=5,Player2=4,Player3=3,Player4=2,Player5=2},
     {Player1=5,Player2=4,Player3=3,Player4=2,Player5=2}}
})
assert(Core.OpenAwards(one) and not next(one.awards.ties) and Core.ConfirmAwards(one))
assert(one.awards.results[4].name=="Player4")
local empty=qualified(1,{{}})
assert(Core.OpenAwards(empty) and #empty.awards.results==0 and Core.ConfirmAwards(empty))
fails(Core.RevealAward(empty))
print("Core spec passed")
