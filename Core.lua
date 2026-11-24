-- Strut Your Bootsy: UI-independent contest rules (Retail).
-- This module deliberately has no WoW API dependencies.
local addonName, ns = ...
ns = ns or {}
local Core = {}
ns.Core = Core

local roles = { contestant = true, spectator = true }
local function countContestants(state)
    local n = 0
    for _, p in pairs(state.participants) do
        if p.role == "contestant" then n = n + 1 end
    end
    return n
end

function Core.ValidRounds(rounds)
    return type(rounds)=="number" and rounds%1==0 and rounds>=1 and rounds<=5
end

function Core.New(admin, rounds)
    assert(type(admin) == "string" and admin ~= "", "admin required")
    rounds = rounds or 1
    assert(Core.ValidRounds(rounds), "rounds must be 1-5")
    return {
        admin = admin, phase = "registration", rounds = rounds, round = 0,
        participants = {}, order = {}, scores = {}, ballots = {},
        version = 1,
    }
end

function Core.Register(state, player, role)
    if state.phase ~= "registration" then return false, "registration_closed" end
    if type(player) ~= "string" or player == "" then return false, "invalid_player" end
    if player == state.admin then return false, "admin_cannot_participate" end
    if not roles[role] then return false, "invalid_role" end
    if state.participants[player] then return false, "already_registered" end
    state.participants[player] = { role = role }
    state.version = state.version + 1
    return true
end

function Core.CanStart(state, pendingAddonUsers)
    if state.phase ~= "registration" then return false, "wrong_phase" end
    if countContestants(state) < (state.minContestants or 5) then return false, "minimum_five_contestants" end
    if (pendingAddonUsers or 0) > 0 then return false, "registration_pending" end
    return true
end

function Core.Start(state, order, pendingAddonUsers)
    local ok, reason = Core.CanStart(state, pendingAddonUsers)
    if not ok then return false, reason end
    if type(order) ~= "table" or #order ~= countContestants(state) then return false, "invalid_runway_order" end
    local seen = {}
    for _, name in ipairs(order) do
        if seen[name] or not state.participants[name] or state.participants[name].role ~= "contestant" then
            return false, "invalid_runway_order"
        end
        seen[name] = true
    end
    state.order = order
    state.round = 1
    state.phase, state.runwayIndex = "preparation", nil
    state.version = state.version + 1
    return true
end

-- Fisher–Yates over a copy: the caller's roster is not mutated.
function Core.Shuffle(order, random)
    local shuffled = {}
    for i, name in ipairs(order) do shuffled[i] = name end
    for i = #shuffled, 2, -1 do
        local j = 1 + math.floor(random() * i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    return shuffled
end

function Core.RunwayStatus(state)
    local i = state.runwayIndex
    if not i then return nil end
    local active = state.phase == "runway"
    return {index=i, total=#state.order, current=active and state.order[i] or nil,
        upcoming=active and state.order[i+1] or nil}
end

function Core.BeginRunway(state)
    if state.phase ~= "preparation" then return false, "wrong_phase" end
    state.phase, state.runwayIndex = "runway", 1
    state.version = state.version + 1
    return true
end

function Core.AdvanceRunway(state)
    if state.phase ~= "runway" then return false, "wrong_phase" end
    if state.runwayIndex >= #state.order then state.phase = "runway_complete"
    else state.runwayIndex = state.runwayIndex + 1 end
    state.version = state.version + 1
    return true
end

function Core.BeginVoting(state)
    if state.phase ~= "runway_complete" then return false, "wrong_phase" end
    state.phase = "voting"
    state.ballots[state.round] = {}
    state.version = state.version + 1
    return true
end

-- Caller must verify roster membership and sender identity. All valid raid members
-- except the admin may vote; addon installation is checked by the WoW adapter.
function Core.SubmitBallot(state, voter, ratings)
    if state.phase ~= "voting" then return false, "voting_closed" end
    if voter == state.admin then return false, "admin_cannot_vote" end
    if type(voter) ~= "string" or voter == "" or type(ratings) ~= "table" then return false, "invalid_ballot" end
    if state.ballots[state.round][voter] then return false, "ballot_already_submitted" end
    local sanitized, n = {}, 0
    for contestant, score in pairs(ratings) do
        if not state.participants[contestant] or state.participants[contestant].role ~= "contestant" then
            return false, "unknown_contestant"
        end
        if contestant == voter then return false, "self_vote" end
        if type(score) ~= "number" or score % 1 ~= 0 or score < 1 or score > 5 then
            return false, "rating_out_of_range"
        end
        sanitized[contestant] = score
        n = n + 1
    end
    if n == 0 then return false, "empty_ballot" end
    state.ballots[state.round][voter] = sanitized
    state.version = state.version + 1
    return true
end

function Core.CloseVoting(state, minimumRatings)
    if state.phase ~= "voting" then return false, "wrong_phase" end
    local totals, counts = {}, {}
    for _, ratings in pairs(state.ballots[state.round]) do
        for name, rating in pairs(ratings) do
            totals[name] = (totals[name] or 0) + rating
            counts[name] = (counts[name] or 0) + 1
        end
    end
    state.scores[state.round] = {}
    for _, name in ipairs(state.order) do
        if (counts[name] or 0) >= (minimumRatings or 1) then state.scores[state.round][name] = totals[name] / counts[name] end
    end
    state.phase = "round_results"
    state.version = state.version + 1
    return true
end

function Core.NextRound(state)
    if state.phase ~= "round_results" then return false, "wrong_phase" end
    if state.round >= state.rounds then return false, "final_round" end
    state.round = state.round + 1
    state.phase, state.runwayIndex = "preparation", nil
    state.version = state.version + 1
    return true
end

function Core.FinalResults(state)
    if state.phase ~= "round_results" or state.round ~= state.rounds then
        return nil, "not_finished"
    end
    local results = {}
    for _, name in ipairs(state.order) do
        local total, qualified = 0, true
        for r = 1, state.rounds do
            local score = state.scores[r] and state.scores[r][name]
            if not score then qualified = false; break end
            total = total + score
        end
        if qualified then results[#results + 1] = { name = name, average = total / state.rounds } end
    end
    table.sort(results, function(a, b)
        if a.average == b.average then return a.name < b.name end
        return a.average > b.average
    end)
    -- Tied podium positions require the separate approved /roll 100 workflow.
    return results
end

-- Uses the unrounded per-round scores, weighted equally across rounds.
-- Missing any round disqualifies an entry from the cumulative standings.
function Core.Cumulative(state)
    local scores={}
    for _,name in ipairs(state.order) do
        local sum,complete=0,true
        for round=1,state.round do
            local score=state.scores[round] and state.scores[round][name]
            if not score then complete=false;break end
            sum=sum+score
        end
        if complete and state.round>0 then scores[name]=sum/state.round end
    end
    return scores
end

-- Tie blocks that touch places 1-3 need verified /roll 100 results.
-- The leader explicitly records observed rolls; equal rolls require reroll
-- only among the affected entries. Roll data never appears in raid packets.
function Core.OpenAwards(state)
    local results,why=Core.FinalResults(state)
    if not results then return false,why end
    state.awards={results=results,rolls={},ties={},tieRanges={},revealed=0}
    local i=1
    while i<=#results and i<=3 do
        local j=i+1
        while j<=#results and math.abs(results[j].average-results[i].average)<1e-9 do j=j+1 end
        if j>i+1 then
            state.awards.tieRanges[#state.awards.tieRanges+1]={first=i,last=j-1}
            for k=i,j-1 do state.awards.ties[results[k].name]=i end
        end
        i=j
    end
    state.phase="final_results"
    return true
end

function Core.RecordRoll(state,name,n)
    local a=state.awards
    if state.phase~="final_results" or not a or a.confirmed then return false,"wrong_phase" end
    if not a.ties[name] or type(n)~="number" or n%1~=0 or n<1 or n>100 then return false,"invalid_roll" end
    a.rolls[name]=n
    return true
end

function Core.ConfirmAwards(state)
    local a=state.awards
    if state.phase~="final_results" or not a or a.confirmed then return false,"wrong_phase" end
    local used,redo={},{ }
    for name,group in pairs(a.ties) do
        local value=a.rolls[name]
        if not value then return false,"rolls_required" end
        used[group]=used[group] or {}
        local prior=used[group][value]
        if prior then redo[name],redo[prior]=true,true end
        used[group][value]=name
    end
    if next(redo) then
        for name in pairs(redo) do a.rolls[name]=nil end
        return false,"reroll_required"
    end
    for _,range in ipairs(a.tieRanges) do
        local group={}
        for i=range.first,range.last do group[#group+1]=a.results[i] end
        table.sort(group,function(l,r) return a.rolls[l.name]>a.rolls[r.name] end)
        for i,r in ipairs(group) do a.results[range.first+i-1]=r end
    end
    a.confirmed=true
    return true
end

function Core.RevealAward(state)
    local a=state.awards
    if state.phase~="final_results" or not a or not a.confirmed or a.revealed>=math.min(3,#a.results) then return false,"wrong_phase" end
    a.revealed=a.revealed+1
    return true
end

function Core.Pause(state)
    if state.phase == "paused" or state.phase == "ended" then return false, "wrong_phase" end
    state.previousPhase = state.phase
    state.phase = "paused"
    state.version = state.version + 1
    return true
end

function Core.Resume(state)
    if state.phase ~= "paused" then return false, "wrong_phase" end
    state.phase = state.previousPhase
    state.previousPhase = nil
    state.version = state.version + 1
    return true
end

function Core.End(state)
    state.phase = "ended"
    state.version = state.version + 1
    return true
end
