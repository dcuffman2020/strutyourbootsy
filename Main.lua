local addonName, ns = ...
local Core, Network, UI = ns.Core, ns.Network, ns.UI
local frame = CreateFrame("Frame")
local state, developmentState, network
local roleRequest, notice
local practice, practiceCounter
local raidCustomTheme
local practiceVoter="Cinderstep"
local unpack=unpack or table.unpack
local sequence = 0
local lastSession = 0
local alphaThemes = {"Royalty", "Out of This World", "Back from the Dead", "Heroes of Azeroth"}
local liveThemes = {
    "Royalty", "Out of This World", "Back from the Dead", "Heroes of Azeroth",
    "A Night at the Opera", "Alchemist", "Ancient Guardian", "Arcane Academy", "Arctic Expedition",
    "Autumn Leaves", "Battlefield Medic", "Black and White", "Clockwork", "Cloud Kingdom",
    "Court Jester", "Dark Forest", "Day at the Faire", "Deep Sea", "Desert Wanderer",
    "Dragon Rider", "Dreamwalker", "Elemental Fury", "Emerald Dream", "Enchanted Garden",
    "Festival of Fire", "First Day Adventurer", "Forgotten Relic", "Frost and Flame", "Golden Hour",
    "Grand Masquerade", "Green and Gold", "Haunted Manor", "High Seas", "Into the Wild",
    "Midnight Market", "Monochrome", "Moonlight", "Mountain Explorer", "Mystic Librarian",
    "Nobles and Rogues", "Northrend", "Old School Azeroth", "On the Red Carpet", "Pirate Crew",
    "Rainy Day", "Retro Hero", "Shadows", "Starlight", "Treasure Hunter", "Winter Gala",
}
local raidThemes={}
local function chooseLiveTheme(round)
    if raidCustomTheme then return raidCustomTheme end
    if not raidThemes[round] then
        local used,options={},{}
        for r=1,round-1 do if raidThemes[r] then used[raidThemes[r]]=true end end
        for _,theme in ipairs(liveThemes) do if not used[theme] then options[#options+1]=theme end end
        raidThemes[round]=options[math.random(#options)]
    end
    return raidThemes[round]
end

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aStrut Your Bootsy:|r " .. message)
end

-- Only a successful, locally initiated host transition may reach this path.
-- No warnings are triggered by network messages, refresh, or timer ticks.
local raidWarnings={}

local function sendRaidWarning(key, text)
    if practice or not IsInRaid() or not network or not network:IsAuthority()
        or network.originalLeader~=network.leader or not network.sessionId then return false,"not_raid_leader" end
    if raidWarnings.session~=network.sessionId then raidWarnings={session=network.sessionId} end
    if raidWarnings[key] then return false,"already_announced" end
    local api=C_ChatInfo and C_ChatInfo.SendChatMessage
    if type(api)~="function" then return false,"warning_unavailable" end
    raidWarnings[key]=true -- No automated replay or duplicate if delivery is ambiguous.
    local ok,result=pcall(api,text,"RAID_WARNING")
    if not ok or result==false then
        raidWarnings[key]=nil
        return false,"warning_unavailable"
    end
    return true
end

local function phaseWarning(key, text)
    local ok, reason=sendRaidWarning(key,"Strut Your Bootsy: "..text)
    if not ok and reason=="warning_unavailable" then say("Raid Warning unavailable: "..text) end
end

local function presenterWarning(contest, opening)
    local turn=Core.RunwayStatus(contest)
    if not turn or not turn.current then return end
    return ("turn_%d_%d"):format(contest.round,turn.index),
        (opening and "The runway has begun. " or "")..
        ("Now presenting (%d/%d): %s."):format(turn.index,turn.total,turn.current)
end

local function winnerWarning(names)
    return "Congratulations to "..table.concat(names," ").."!"
end

local function practiceWarning(text)
    local preview="[Practice] "..text
    local color=ChatTypeInfo and ChatTypeInfo.RAID_WARNING
    local shown=false
    if type(RaidNotice_AddMessage)=="function" and RaidWarningFrame and color then
        shown=pcall(RaidNotice_AddMessage,RaidWarningFrame,preview,color)
    end
    if not shown and UIErrorsFrame and type(UIErrorsFrame.AddMessage)=="function" then
        UIErrorsFrame:AddMessage(preview,1,.82,0,1)
    end
    local play=(C_Sound and C_Sound.PlaySound) or PlaySound
    if type(play)=="function" and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        pcall(play,SOUNDKIT.RAID_WARNING)
    end
    say("[Practice Raid Warning] "..text)
end

local function localRealm()
    return GetNormalizedRealmName()
end

local function playerName()
    local name, realm = UnitFullName("player")
    return Network.NormalizeName(name, realm ~= "" and realm or localRealm())
end

local function raidRoster()
    local rows = {}
    if not IsInRaid() then return rows end
    for index = 1, GetNumGroupMembers() do
        local unit = "raid" .. index
        local name, rank, _, _, _, _, _, online = GetRaidRosterInfo(index)
        local character, realm = UnitFullName(unit)
        rows[#rows + 1] = {
            name=character or name, realm=realm, guid=UnitGUID(unit), connected=online, leader=rank == 2,
        }
    end
    return rows
end

local function commandId()
    sequence = sequence + 1
    return ("%d-%d-%d"):format(GetServerTime(), math.floor(GetTime() * 1000), sequence)
end

local liveBallot={ratings={}}
local votePageRequested={}
local function resetLiveBallot()
    liveBallot={ratings={}}
    votePageRequested={}
end
local teamConfig,teamRequest=nil,nil
local lastTeamQuery=0
local function onNetworkEvent(event, data)
    if event == "session_started" then
        resetLiveBallot()
        teamRequest=nil
        raidCustomTheme,raidThemes=nil,{}
        state = Core.New(data.leader, data.rounds)
        notice = nil
    elseif event == "authority_changed" then
        notice = "authority_changed"
    elseif event == "session_ended" and state then
        Core.End(state)
    elseif event=="team_changed" and teamRequest and network.teams and network.teams.revision>teamRequest.revision then
        teamRequest=nil
        notice=nil
    elseif event=="request_result" and teamRequest and teamRequest.id==data.commandId then
        if data.status=="rejected" then
            teamRequest=nil
            notice=data.reason
            if data.reason=="snapshot_mismatch" then network:Poll() end
        end
    elseif event=="request_result" and liveBallot.id==data.commandId then
        if data.status=="rejected" then notice=data.reason end
    elseif event == "request_result" and roleRequest and roleRequest.id == data.commandId then
        notice = data.status == "rejected" and data.reason or nil
        if data.reason == "snapshot_mismatch" then network:Poll() end
    end
    UI.Refresh()
end

local function onNetworkCommand(action, sender, message)
    if not state then return false, "no_session" end
    if action == "ROLE" then return Core.Register(state, sender, message.role) end
    if action == "START" then
        local projection = network:GetProjection()
        local order = {}
        if network.teams then
            local t=network.teams
            local ready,reason=ns.Teams.Readiness(t,network.roster)
            if not ready then return false,reason end
            local contest=Core.New(state.admin,network.rounds)
            contest.minContestants=3
            for id=1,t.span do
                if t.rows[id] then
                    local entry=ns.Teams.Entry(id)
                    assert(Core.Register(contest,entry,"contestant"))
                    order[#order+1]=entry
                end
            end
            local ok,why=Core.Start(contest,Core.Shuffle(order,math.random),0)
            if ok then state=contest end
            return ok,why,ok and state.order or nil
        end
        for _, member in ipairs(projection.members) do
            if member.presence == "addon_ready" and member.role == "contestant" then
                order[#order + 1] = member.name
            end
        end
        state.rounds=network.rounds
        local ok,reason=Core.Start(state,Core.Shuffle(order,math.random),projection.presence.addon_pending + projection.presence.unknown)
        return ok,reason,ok and state.order or nil
    end
    if action == "BEGIN_RUNWAY" or action == "ADVANCE" then
        local operation = action == "BEGIN_RUNWAY" and Core.BeginRunway or Core.AdvanceRunway
        local ok, reason = operation(state)
        return ok, reason, ok and Core.RunwayStatus(state) or nil
    end
    if action=="BEGIN_VOTING" then
        local ok,reason=Core.BeginVoting(state)
        return ok,reason,state.order
    end
    if action=="VOTE" then return Core.SubmitBallot(state,sender,message.ratings) end
    if action=="CLOSE_VOTING" then
        local ok,reason=Core.CloseVoting(state,2)
        if not ok then return false,reason end
        local results={}
        local scores,cumulative=state.scores[state.round],Core.Cumulative(state)
        for _,name in ipairs(state.order) do results[#results+1]={name=name,average=scores[name],cumulative=cumulative[name]} end
        table.sort(results,function(a,b)
            if a.average==b.average then return a.name<b.name end
            return (a.average or 0)>(b.average or 0)
        end)
        for _,r in ipairs(results) do
            if r.average then r.score=math.floor(r.average*100+.5) end
            if r.cumulative then r.cumulative=math.floor(r.cumulative*100+.5) end
        end
        return true,nil,results
    end
    if action=="NEXT_ROUND" then
        local ok,reason=Core.NextRound(state)
        if ok then state.order=Core.Shuffle(state.order,math.random) end
        return ok,reason,ok and state.order or nil
    end
    local awardsAction=({OPEN_AWARDS=Core.OpenAwards,CONFIRM_AWARDS=Core.ConfirmAwards,REVEAL_AWARD=Core.RevealAward})[action]
    if awardsAction then
        local ok,reason=awardsAction(state)
        return ok,reason,ok and state.awards or nil
    end
    if action=="PAUSE" then return Core.Pause(state) end
    if action=="RESUME" then return Core.Resume(state) end
    if action=="END" then return Core.End(state) end
    return false, "unsupported_command"
end

local function setupNetwork()
    if network then return true end
    local candidate = Network.New({
        now=GetTime, after=C_Timer.After, serverNow=GetServerTime, playerName=playerName, localRealm=localRealm, getRoster=raidRoster,
        newerSession=function(nextId, oldId)
            return tonumber(nextId) and tonumber(oldId) and tonumber(nextId) > tonumber(oldId)
        end,
        registerPrefix=function(prefix)
            C_ChatInfo.RegisterAddonMessagePrefix(prefix)
            return C_ChatInfo.IsAddonMessagePrefixRegistered(prefix)
        end,
        send=function(prefix, message, channel, target)
            local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
            return ok and result == Enum.SendAddonMessageResult.Success
        end,
    }, { onEvent=onNetworkEvent, onCommand=onNetworkCommand, chooseTheme=chooseLiveTheme })
    local ok, reason = candidate:Register()
    if not ok then say("Raid communications unavailable: " .. reason); return false end
    network = candidate
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    network:RefreshRoster()
    return true
end

local function openRegistration()
    if not setupNetwork() then return false, "not_registered" end
    network:RefreshRoster()
    lastSession = math.max(GetServerTime() * 1000, lastSession + 1)
    local id = ("%.0f"):format(lastSession)
    local ok, reason = network:StartSession(id,teamConfig)
    if not ok then return false, reason end
    local queued, delivery = network:BeginDiscovery()
    if queued then phaseWarning("registration","Registration is open. Use /syb to join.") end
    C_Timer.After(Network.DISCOVERY_SECONDS, function()
        if network.sessionId == id and network.phase == "registration" then network:ClassifyDiscovery() end
    end)
    return queued, delivery
end

local function submitRole(role)
    if not network or not network.sessionId then return false, "no_session" end
    local p = network:GetProjection()
    if p.isLeader then return false, "admin_cannot_participate" end
    if p.phase ~= "registration" or p.localRole then return false, "wrong_phase" end
    if p.lobbyState == "late_joiner" or p.lobbyState == "disconnected" then return false, p.lobbyState end
    local old = roleRequest and network.pending[roleRequest.id]
    local ok, reason
    if old and old.status == "pending" then
        ok, reason = network:Retry(roleRequest.id)
    else
        if roleRequest then network.pending[roleRequest.id] = nil end
        local id = commandId()
        ok, reason = network:Request("ROLE", id, {role=role})
        if ok then roleRequest = {id=id} end
    end
    if ok then
        roleRequest.sent = GetTime()
        C_Timer.After(6, UI.Refresh)
    end
    return ok, reason
end

local demoNames = {"Cinderstep", "Valeweaver", "Mossmantle", "Copperwink", "Thistledawn"}

local function grouped()
    return IsInRaid() or (IsInGroup and IsInGroup())
end

local function playCue()
    if SYBCharacterDB.preferences.sounds and PlaySound and SOUNDKIT then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

local function nextPracticePreparation()
    local c, cfg = practice.contest, practice.settings
    local theme = cfg.customTheme
    if not theme and cfg.theme ~= "Random" then theme=cfg.theme end
    if not theme then
        local choices = practice.themePool
        if #choices == 0 then
            for i, v in ipairs(alphaThemes) do choices[i]=v end
        end
        theme = table.remove(choices, 1 + math.floor(math.random() * #choices))
    end
    practice.preparation = {theme=theme,endsAt=GetServerTime()+cfg.prep}
    practice.ballot, practice.ballotSubmitted = {},false
end

local function practiceView()
    local c = practice.contest
    local result,turn
    turn=Core.RunwayStatus(c)
    if turn and c.phase=="runway" then turn.endsAt=practice.turnEndsAt end
    local function labelFor(name)
        local team=name and practice.teams and practice.teams.rows[ns.Teams.EntryID(name)]
        return team and team.name or name
    end
    if turn and practice.teams then
        turn.currentGuid=turn.current
        turn.current,turn.upcoming=labelFor(turn.current),labelFor(turn.upcoming)
    end
    if c.phase == "round_results" then
        result={}
        for _,name in ipairs(c.order) do
            result[#result+1]={name=labelFor(name), average=c.scores[c.round][name]}
        end
        table.sort(result,function(a,b)
            if a.average==b.average then return a.name<b.name end
            return (a.average or 0)>(b.average or 0)
        end)
    end
    return {practice=true,isLeader=true,sessionId=practice.id,phase=c.phase,round=c.round,rounds=c.rounds,
        contestants=#practice.members,spectators=0,pendingResponses=0,members=practice.members,
        teams=practice.teams,completeTeams=practice.teams and 3,unassigned=0,teamRunwayOrder=practice.teams and c.order,
        lobbyState="ready_to_start",discoveryComplete=true,preparation=practice.preparation,preparationSeconds=practice.settings.prep,
        runway=turn,runwaySeconds=practice.runwaySeconds,runwayOrder=c.order,notice=notice,wizard=practice.wizard,
        settings=practice.wizardDraft or practice.settings,customTheme=(practice.wizardDraft or practice.settings).customTheme,ballot=practice.ballot,ballotSubmitted=practice.ballotSubmitted,
        voteEndsAt=practice.voteEndsAt,result=result,reveal=practice.reveal,revealCount=practice.revealCount,
        practiceVoter=practice.teams and "Practice spectator" or practiceVoter,practicePaused=c.phase=="paused"}
end

local function enterPractice(teamMode)
    if grouped() then return false,"practice_solo_only" end
    if not practice then
        practiceCounter=(practiceCounter or 0)+1
        local c=Core.New("Practice host",1)
        local members={}
        for _,name in ipairs(teamMode and {} or demoNames) do
            assert(Core.Register(c,name,"contestant"))
            members[#members+1]={name=name,guid=name,presence="addon_ready",role="contestant"}
        end
        practice={id="practice-"..practiceCounter,contest=c,members=members,ballot={},themePool={},
            settings={rounds=1,theme="Random",prep=Network.PREPARATION_SECONDS,vote=60},runwaySeconds=Network.RUNWAY_SECONDS}
        if teamMode then
            local t=ns.Teams.New(2)
            practice.teams=t
            c.minContestants=3
            for i,names in ipairs({{"Cinderstep","Valeweaver"},{"Mossmantle","Thistledawn"},{"Copperwink","Emberbrook"}}) do
                assert(ns.Teams.Apply(t,names[1],"create",nil,nil,({"Gilded Hounds","Iron Thorns","Moonlit Thread"})[i]))
                assert(ns.Teams.Apply(t,names[2],"join",i))
                assert(Core.Register(c,ns.Teams.Entry(i),"contestant"))
                for _,name in ipairs(names) do members[#members+1]={name=name,guid=name,presence="addon_ready",role="contestant"} end
            end
        end
        practiceWarning("Registration is open. Use /syb to join.")
    end
    notice=nil
    UI.Show()
    return true
end

local function leavePractice()
    practice,notice=nil,nil
    UI.Refresh()
end

local function practiceAction(action, argument, value)
    if not practice or grouped() then return false,"practice_solo_only" end
    local c,cfg=practice.contest,practice.settings
    if action=="SETUP" and c.phase=="registration" then
        practice.wizard,practice.wizardDraft=1,{rounds=cfg.rounds,theme=cfg.theme,customTheme=cfg.customTheme,prep=cfg.prep,vote=cfg.vote}
        return true
    end
    if practice.wizard then
        if action=="BACK" then
            practice.wizard=practice.wizard>1 and practice.wizard-1 or nil
            if not practice.wizard then practice.wizardDraft=nil end
        elseif action=="CONTINUE" then
            if practice.wizard==5 then
                practice.settings,practice.wizardDraft,practice.wizard=practice.wizardDraft,nil,nil
            else practice.wizard=practice.wizard+1 end
        elseif action=="SETTING" then
            local options=({[1]={rounds={1,2,3,4,5}},[2]={theme={"Random",unpack(alphaThemes)}},
                [3]={prep={60,unpack(Network.PREPARATION_OPTIONS)}},[4]={vote={30,60,90}}})[practice.wizard]
            local valid=false
            for _,choice in ipairs(options and options[argument] or {}) do if choice==value then valid=true end end
            if not valid then return false,"invalid_setting" end
            practice.wizardDraft[argument]=value
            if argument=="theme" then practice.wizardDraft.customTheme=nil end
        else return false,"wrong_phase" end
        return true
    end
    if action=="START" then
        if c.phase~="registration" then return false,"wrong_phase" end
        c.rounds=cfg.rounds
        local ok,reason=Core.Start(c,Core.Shuffle(practice.teams and {"Team-1","Team-2","Team-3"} or demoNames,math.random),0)
        if not ok then return false,reason end
        nextPracticePreparation()
        playCue()
        return true
    end
    if action=="BEGIN_RUNWAY" then
        if not practice.preparation or GetServerTime()<practice.preparation.endsAt then return false,"preparation_running" end
        local ok,reason=Core.BeginRunway(c)
        if ok then practice.turnEndsAt=GetServerTime()+practice.runwaySeconds end
        return ok,reason
    end
    if action=="ADVANCE" then
        local ok,reason=Core.AdvanceRunway(c)
        if ok and c.phase=="runway" then practice.turnEndsAt=GetServerTime()+practice.runwaySeconds end
        return ok,reason
    end
    if action=="PAUSE" and c.phase=="runway" then
        practice.turnRemaining=math.max(0,practice.turnEndsAt-GetServerTime())
        return Core.Pause(c)
    end
    if action=="RESUME" and c.phase=="paused" then
        local ok,reason=Core.Resume(c)
        if ok then practice.turnEndsAt=GetServerTime()+practice.turnRemaining end
        return ok,reason
    end
    if action=="VOTING" then
        local ok,reason=Core.BeginVoting(c)
        if not ok then return false,reason end
        practice.voteEndsAt=GetServerTime()+cfg.vote
        playCue()
        return true
    end
    if action=="RATE" then
        if c.phase~="voting" or GetServerTime()>=practice.voteEndsAt or practice.ballotSubmitted then return false,"voting_closed" end
        if not c.participants[argument] or argument==practiceVoter or type(value)~="number" or value%1~=0 or value<1 or value>5 then return false,"invalid_rating" end
        if practice.ballot[argument]==value then practice.ballot[argument]=nil else practice.ballot[argument]=value end
        return true
    end
    if action=="SUBMIT" then
        if c.phase~="voting" or GetServerTime()>=practice.voteEndsAt then return false,"voting_closed" end
        local ok,reason=Core.SubmitBallot(c,practice.teams and "Practice spectator" or practiceVoter,practice.ballot)
        if ok then practice.ballotSubmitted=true end
        return ok,reason
    end
    if action=="CLOSE_VOTE" then
        if c.phase~="voting" or GetServerTime()<practice.voteEndsAt then return false,"voting_running" end
        local ok,reason=Core.CloseVoting(c)
        if ok then playCue() end
        return ok,reason
    end
    if action=="NEXT_ROUND" then
        local ok,reason=Core.NextRound(c)
        if not ok then return false,reason end
        c.order=Core.Shuffle(c.order,math.random)
        nextPracticePreparation()
        return true
    end
    if action=="AWARDS" then
        local winners,reason=Core.FinalResults(c)
        if not winners then return false,reason end
        if practice.teams then for _,r in ipairs(winners) do r.name=practice.teams.rows[ns.Teams.EntryID(r.name)].name end end
        for i=1,math.min(3,#winners-1) do
            if winners[i].average==winners[i+1].average then return false,"practice_tie" end
        end
        practice.reveal=winners
        practice.revealCount=0
        return true
    end
    if action=="REVEAL" and practice.reveal then
        practice.revealCount=math.min(#practice.reveal,3,practice.revealCount+1)
        return true
    end
    return false,"unsupported_command"
end

local function runPracticeAction(action,...)
    local ok,reason=practiceAction(action,...)
    if not ok then return ok,reason end
    local c=practice.contest
    if action=="START" or action=="NEXT_ROUND" then
        practiceWarning(("Round %d preparation is open. Theme: %s."):format(c.round,practice.preparation.theme))
    elseif action=="BEGIN_RUNWAY" or action=="ADVANCE" then
        if c.phase=="runway_complete" then
            practiceWarning(("Round %d runway is complete."):format(c.round))
        else
            local _,message=presenterWarning(c,action=="BEGIN_RUNWAY")
            if message and practice.teams then
                local turn=Core.RunwayStatus(c)
                message="Now presenting: "..practice.teams.rows[ns.Teams.EntryID(turn.current)].name.."."
            end
            if message then practiceWarning(message) end
        end
    elseif action=="VOTING" then
        practiceWarning(("Round %d voting is open."):format(c.round))
    elseif action=="CLOSE_VOTE" then
        local best,names=nil,{}
        for _,name in ipairs(c.order) do
            local score=c.scores[c.round][name]
            if score and (not best or score>=best) then
                if score~=best then best,names=score,{} end
                names[#names+1]=practice.teams and practice.teams.rows[ns.Teams.EntryID(name)].name or name
            end
        end
        local result=#names>0 and (" Top score: "..table.concat(names,", ")..".") or ""
        practiceWarning(("Round %d voting is closed."):format(c.round)..result)
    elseif action=="REVEAL" and not practice.podiumAnnounced then
        local n=math.min(#practice.reveal,3)
        if n>0 and practice.revealCount==n then
            local names={}
            for i=1,n do names[i]=practice.reveal[i].name end
            practice.podiumAnnounced=true
            practiceWarning(winnerWarning(names))
        end
    end
    return ok,reason
end

local function view()
    if practice then return practiceView() end
    local p = network and network:GetProjection() or {}
    local pending = roleRequest and network and network.pending[roleRequest.id]
    p.teamSetupSize=teamConfig
    if p.teams then
        p.teamMine=p.teams.byMember[p.localGuid or ""]
        p.teamPending=teamRequest and teamRequest.session==p.sessionId and GetTime()-teamRequest.sent<6
    end
    if not p.teams and p.lobbyState == "ready_to_start" and state then
        local ready, reason = Core.CanStart(state, p.pendingResponses + p.presence.unknown)
        if not ready then p.lobbyState = reason end
    end
    if p.isLeader and p.phase=="registration" then
        p.customTheme,p.runwaySeconds,p.preparationSeconds=raidCustomTheme,network.runwaySeconds,network.preparationSeconds
    end
    if p.isLeader and state and p.runway then
        p.runwayOrder,p.runwayGuids=state.order,network.contestantGuids
        if p.teams then
            p.teamRunwayOrder=state.order
            p.runwayOrder=nil
        end
    end
    if liveBallot.session~=p.sessionId or liveBallot.round~=p.round then
        if liveBallot.id and network then network.pending[liveBallot.id]=nil end
        resetLiveBallot()
        liveBallot.session,liveBallot.round=p.sessionId,p.round
    end
    if p.isLeader and p.phase=="final_results" and state and state.awards and not state.awards.confirmed then
        p.tieRolls={}
        local a=state.awards
        for _,r in ipairs(a.results) do
            if a.ties[r.name] then
                local team=network.teams and network.teams.rows[ns.Teams.EntryID(r.name)]
                p.tieRolls[#p.tieRolls+1]={entry=r.name,name=team and team.name or r.name,value=a.rolls[r.name],group=a.ties[r.name]}
            end
        end
    end
    local voting=network and network.voting
    if voting and (p.phase=="voting" or p.phase=="round_results") then
        p.voteEndsAt,p.voteTotal=voting.endsAt,voting.total
        p.voteSubmitted=network.voted==true
        p.voterEligible=not p.isLeader and p.localRole~=nil and p.lobbyState~="late_joiner" and p.lobbyState~="disconnected"
        p.ballot=liveBallot.ratings
        local request=liveBallot.id and network.pending[liveBallot.id]
        p.ballotPending=request and request.status=="pending"
        p.ballotRetry=p.ballotPending and GetTime()-(liveBallot.sent or 0)>=6
    end
    p.notice = notice
    if not p.localRole and pending and pending.status == "pending" then
        p.submittedRole = pending.message.role
        p.awaiting = GetTime() - roleRequest.sent < 6
        p.timedOut = not p.awaiting
    end
    return p
end

local function getVotePage(page)
    local rows=network and network:GetVotePage(page)
    if not rows then return end
    local names={}
    for name,member in pairs(network.roster) do names[member.guid]=name end
    for name,member in pairs(network.absent) do names[member.guid]=name end
    local display={}
    for i,row in ipairs(rows) do
        local teamID=network.teams and ns.Teams.EntryID(row.guid)
        local team=teamID and network.teams.rows[teamID]
        display[i]={guid=row.guid,index=row.index,name=teamID and (team and team.name or "Team "..teamID) or names[row.guid],
            score=row.score,cumulative=row.cumulative,masked=row.guid=="-",team=teamID,ownTeam=teamID and network.teams.byMember[UnitGUID("player")]==teamID,
            teamData=team,teamSize=teamID and network.teams.size,memberNames=teamID and names}
    end
    return display
end

local function requestVotePage(page)
    if not network or not (network.voting or network.runway) or network:IsAuthority() then return end
    local key=network.sessionId..":"..network.version..":"..page
    if not votePageRequested[key] or GetTime()-votePageRequested[key]>=6 then
        votePageRequested[key]=GetTime()
        network:RequestVotePage(page)
    end
end

local function rateLive(row, n)
    local p=view()
    if not p.voterEligible or p.phase~="voting" or p.voteSubmitted or p.ballotPending
        or GetServerTime()>=p.voteEndsAt or not row.name or row.name==playerName() or row.ownTeam then return end
    local page=math.ceil(row.index/Network.VOTE_PAGE_SIZE)
    local rows=getVotePage(page)
    local current=rows and rows[(row.index-1)%Network.VOTE_PAGE_SIZE+1]
    if not current or current.guid~=row.guid then return end
    liveBallot.ratings[row.index]=liveBallot.ratings[row.index]~=n and n or nil
    notice=nil
    UI.Refresh()
end

local function submitLiveBallot()
    local p=view()
    if not p.voterEligible or p.phase~="voting" or p.voteSubmitted or GetServerTime()>=p.voteEndsAt then return false,"voting_closed" end
    local ok,reason
    if p.ballotPending then
        if not p.ballotRetry then return false end
        ok,reason=network:Retry(liveBallot.id)
    else
        if not next(liveBallot.ratings) then return false,"empty_ballot" end
        local ratings={}
        for i=1,p.voteTotal do ratings[i]=tostring(liveBallot.ratings[i] or 0) end
        local id=commandId()
        ok,reason=network:Request("VOTE",id,{ratings=table.concat(ratings)})
        if ok then liveBallot.id=id end
    end
    if ok then
        liveBallot.sent=GetTime()
        C_Timer.After(6,UI.Refresh)
    end
    return ok,reason
end

local function queryTeam()
    if not network or not network.teams or network:IsAuthority() then return end
    local now=GetTime()
    if now<lastTeamQuery then return end
    local t=network.teams
    for i=1,t.span do
        if not (t.known and t.known[i]) then
            lastTeamQuery=now+1.25
            network:RequestTeam(i)
            return
        end
    end
end

local function doTeamAction(op,slot,other,value)
    if not network or not network.teams or network.phase~="registration" then return false,"wrong_phase" end
    if (op=="create" or op=="rename") and not ns.Teams.Name(value) then return false,"team_name_invalid" end
    if teamRequest and teamRequest.session==network.sessionId and GetTime()-teamRequest.sent<6 then return false end
    local id=commandId()
    local ok,reason=network:Request("TEAM",id,{op=op,slot=slot,other=other,txt=value})
    if ok then
        teamRequest={id=id,session=network.sessionId,sent=GetTime(),revision=network.teams.revision}
        C_Timer.After(6,function()
            if teamRequest and teamRequest.id==id and network then
                local pending=network.pending[id]
                if pending and pending.status=="pending" then network:Retry(id) end
                network:Poll()
                UI.Refresh()
            end
        end)
    end
    return ok,reason
end

local function setLiveRounds(n)
    if practice or not network then return false,"wrong_phase" end
    network:RefreshRoster()
    return network:SetRounds(n)
end

local function setPreparationSeconds(seconds)
    if not Network.ValidPreparationSeconds(seconds) and not (practice and seconds==60) then return false,"invalid_setting" end
    if practice then
        if grouped() or practice.contest.phase~="registration" or practice.wizard then return false,"wrong_phase" end
        practice.settings.prep=seconds
        return true
    end
    if not network then return false,"not_registered" end
    network:RefreshRoster()
    local p=network:GetProjection()
    if not p.isLeader or p.phase~="registration" or network.originalLeader~=network.leader then
        return false,"not_raid_leader"
    end
    network.preparationSeconds=seconds
    return true
end

local function setRunwaySeconds(seconds)
    if not Network.ValidRunwaySeconds(seconds) then return false,"invalid_setting" end
    if practice then
        if grouped() or practice.contest.phase~="registration" then return false,"wrong_phase" end
        practice.runwaySeconds=seconds
        return true
    end
    if not network then return false,"not_registered" end
    network:RefreshRoster()
    local p=network:GetProjection()
    if not p.isLeader or p.phase~="registration" or network.originalLeader~=network.leader then
        return false,"not_raid_leader"
    end
    network.runwaySeconds=seconds
    return true
end

local function setCustomTheme(text)
    local label = text==nil and nil or Network.NormalizeCustomTheme(text)
    if text~=nil and not label then return false,"invalid_theme" end
    if practice then
        if grouped() or practice.contest.phase~="registration" then return false,"wrong_phase" end
        local settings=practice.wizardDraft or practice.settings
        settings.customTheme=label
        if not label then settings.theme="Random" end
        notice=nil
        return true
    end
    if not network then return false,"not_registered" end
    network:RefreshRoster()
    local p=network:GetProjection()
    if not p.isLeader or p.phase~="registration" or network.originalLeader~=network.leader then
        return false,"not_raid_leader"
    end
    raidCustomTheme=label
    notice=nil
    return true
end

local function refresh()
    if practice then
        if not grouped() then UI.Refresh(); return end
        leavePractice()
    end
    if network then
        network:RefreshRoster()
        network:Poll()
    end
end

local function schedulePoll()
    -- Stagger whispers so a whole raid does not consume the leader's burst budget at once.
    local spread = IsInRaid() and math.max(8, GetNumGroupMembers() * 1.5) or 8
    C_Timer.After(8 + math.random() * spread, function()
        refresh()
        schedulePoll()
    end)
end

local function run(action, ...)
    local ok, reason = action(...)
    notice = nil
    if not ok then notice = reason end
    UI.Refresh()
    return ok, reason
end

local function adminAction(action)
    if practice then return runPracticeAction(action) end
    if not network then return false,"not_registered" end
    local ok, reason = network:AdminCommand(action,commandId())
    if not ok then return false,reason end
    local round=network.round
    if (action=="START" or action=="NEXT_ROUND") and network.preparation then
        phaseWarning("preparation_"..round,("Round %d of %d preparation is open. Theme: %s."):format(
            round,network.rounds,network.preparation.theme))
    elseif action=="BEGIN_RUNWAY" or action=="ADVANCE" then
        if network.phase=="runway_complete" then
            phaseWarning("runway_complete_"..round,("Round %d runway is complete."):format(round))
        else
            local key,message=presenterWarning(state,action=="BEGIN_RUNWAY")
            if key then if network.teams then
                    local turn=Core.RunwayStatus(state)
                    local team=network.teams.rows[ns.Teams.EntryID(turn.current)]
                    message=("Now presenting team %d of %d: %s."):format(turn.index,turn.total,team and team.name or turn.current)
                end
                phaseWarning(key,message) end
        end
    end
    local id, version = network.sessionId, network.version
    if action=="BEGIN_VOTING" or (action=="RESUME" and network.phase=="voting") then
        if action=="BEGIN_VOTING" then
            phaseWarning("voting_open_"..round,("Round %d voting is open for %d seconds."):format(round,Network.VOTING_SECONDS))
        end
        local vote=network.voting
        local function closeAtDeadline()
            if not network or network.sessionId~=id or network.round~=round or network.phase~="voting"
                or network.version~=version or network.voting~=vote or not network:IsAuthority() then return end
            local remaining=vote.endsAt-GetServerTime()
            if remaining>0 then C_Timer.After(remaining,closeAtDeadline) else run(adminAction,"CLOSE_VOTING") end
        end
        C_Timer.After(math.max(0,vote.endsAt-GetServerTime()),closeAtDeadline)
    elseif action=="CLOSE_VOTING" then
        local results=network.voting.results
        local leaders={}
        for _,r in ipairs(results) do
            if r.average and r.average==results[1].average then
                local team=network.teams and network.teams.rows[ns.Teams.EntryID(r.name)]
                leaders[#leaders+1]=team and team.name or r.name
            end
        end
        local names=table.concat(leaders,", ")
        phaseWarning("voting_closed_"..round,("Round %d voting is closed. "):format(round)..(#leaders==0 and "No entry qualified."
            or (#names<=165 and "Top score: "..names.."." or "See the tied leaders in the round results.")))
    elseif action=="OPEN_AWARDS" and not next(state.awards.ties) then
        -- Confirm automatically only when there are no podium ties to verify.
        return adminAction("CONFIRM_AWARDS")
    elseif action=="REVEAL_AWARD" then
        local a=state.awards
        local slot=math.min(3,#a.results)-a.revealed+1
        local function entryName(entry)
            local team=network.teams and network.teams.rows[ns.Teams.EntryID(entry.name)]
            return team and team.name or entry.name
        end
        local message=("%s place: %s!"):format(({"First","Second","Third"})[slot],entryName(a.results[slot]))
        if slot==1 and a.results[4] then message=message.." Honorable Mention: "..entryName(a.results[4]).."." end
        phaseWarning("placement_"..slot,message)
    end
    local function publish()
        if not practice and network.sessionId==id and network.version==version then
            local ok=network:BroadcastContest()
            if ok and network.voting then network:BroadcastVotePage(1) end
            return ok
        end
    end
    if not publish() then C_Timer.After(Network.SEND_WINDOW+0.25,publish) end
    return true
end

local function recordLiveRoll(entry,value)
    if practice or not state or not network then return false,"wrong_phase" end
    network:RefreshRoster()
    if not network:IsAuthority() or network.originalLeader~=network.leader then return false,"not_raid_leader" end
    if network.phase~="final_results" then return false,"wrong_phase" end
    return Core.RecordRoll(state,entry,value)
end

local function announceWinners(input)
    if practice or not state or not network then return false,"Finish a live runway first." end
    network:RefreshRoster()
    if not IsInRaid() or not network:IsAuthority() or network.originalLeader~=network.leader then
        return false,"Only the contest’s raid leader can announce winners."
    end
    if network.phase~="runway_complete" or network.teams then return false,"Use the solo runway to announce a manual podium." end
    local names,seen={},{}
    for token in input:gmatch("%S+") do
        local matches={}
        for _,name in ipairs(state.order) do
            local full=name:lower()
            if token==full or token==full:match("^[^-]+") then matches[#matches+1]=name end
        end
        if #matches~=1 or seen[matches[1]] then
            return false,"Use three different contestants from this runway. Add -Realm if a name is ambiguous."
        end
        local name=matches[1]
        seen[name]=true
        names[#names+1]=name
    end
    if #names~=3 then return false,"Usage: /syb announce winners First Second Third" end
    local ok,reason=sendRaidWarning("podium",winnerWarning(names))
    if ok then return true end
    if reason=="already_announced" then return false,"Winners have already been announced for this contest." end
    return false,"Could not send the winners as a Raid Warning."
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        SYBCharacterDB = SYBCharacterDB or {preferences={}}
        SYBCharacterDB.preferences = SYBCharacterDB.preferences or {}
        setupNetwork()
        UI.Initialize({
            getProjection=view, playerName=playerName, refresh=refresh, preferences=SYBCharacterDB.preferences,
            serverNow=GetServerTime, preparationMax=Network.PREPARATION_MAX,
            preparationOptions=Network.PREPARATION_OPTIONS,setPreparationSeconds=setPreparationSeconds,
            normalizeTheme=Network.NormalizeCustomTheme,setCustomTheme=setCustomTheme,
            setRunwaySeconds=setRunwaySeconds,runwayOptions=Network.RUNWAY_OPTIONS,
            groupActive=grouped, enterPractice=function() run(enterPractice) end,
            practiceAction=function(...) run(runPracticeAction,...) end,
            skipVote=function()
                if practice and practice.contest.phase=="voting" then practice.voteEndsAt=GetServerTime(); UI.Refresh() end
            end,
            openRegistration=function() run(openRegistration) end,
            start=function() run(adminAction,"START") end,
            beginRunway=function() run(adminAction,"BEGIN_RUNWAY") end,
            beginVoting=function() run(adminAction,"BEGIN_VOTING") end,
            endContest=function() run(adminAction,"END") end,
            setLiveRounds=function(n) return run(setLiveRounds,n) end,
            nextRound=function() run(adminAction,"NEXT_ROUND") end,
            openAwards=function() run(adminAction,"OPEN_AWARDS") end,
            confirmAwards=function() run(adminAction,"CONFIRM_AWARDS") end,
            revealAward=function() run(adminAction,"REVEAL_AWARD") end,
            recordRoll=function(...) return run(recordLiveRoll,...) end,
            pauseLive=function() run(adminAction,"PAUSE") end,
            resumeLive=function() run(adminAction,"RESUME") end,
            setContestFormat=function(size)
                if not practice and (not network or not network.sessionId or network.phase=="ended") then
                    teamConfig=ns.Teams.ValidSize(size) and size or nil
                end
                UI.Refresh()
            end,
            queryTeam=queryTeam,teamAction=function(...) return run(doTeamAction,...) end,
            getVotePage=getVotePage, requestVotePage=requestVotePage, votePageSize=Network.VOTE_PAGE_SIZE,
            rateLive=rateLive, submitLiveBallot=function() run(submitLiveBallot) end,
            advanceRunway=function() run(adminAction,"ADVANCE") end,
            leavePractice=leavePractice,
            restartPractice=function() local teamMode=practice and practice.teams~=nil;leavePractice();enterPractice(teamMode) end,
            skipPreparation=function()
                if practice and practice.contest.phase=="preparation" and practice.preparation then
                    practice.preparation.endsAt=GetServerTime()
                    UI.Refresh()
                end
            end,
            cancel=function() run(function()
                local ok,reason=network:CancelRegistration()
                if ok then phaseWarning("cancelled","Registration was cancelled.") end
                return ok,reason
            end) end,
            submitRole=function(role) run(submitRole, role) end,
            confirmPassive=function(name, guid)
                network:RefreshRoster()
                run(function() return network:ConfirmNoAddon(name, guid) end)
            end,
        })
        schedulePoll()
        say("Loaded. /syb opens the contest window.")
    elseif event == "CHAT_MSG_ADDON" and network and not practice then
        local prefix, message, channel, sender = ...
        if prefix == Network.PREFIX then
            network:RefreshRoster()
            network:Receive(prefix, message, channel, sender)
            UI.Refresh()
        end
    elseif network then
        refresh()
    end
end)

SLASH_STRUTYOURBOOTSY1 = "/syb"
SlashCmdList.STRUTYOURBOOTSY = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "" or input == "show" or input == "toggle" then
        UI.Toggle()
    elseif input == "practice" then
        local ok = enterPractice()
        if not ok then say("Leave your party or raid before starting solo practice.") end
    elseif input == "teampractice" then
        if practice and not grouped() then leavePractice() end
        run(enterPractice,true)
    elseif input == "practice stop" then
        if practice then leavePractice(); say("Solo practice ended.") end
    elseif input == "status" then
        local p = view()
        local localStatus = p.practice and ("Practice mode: " .. p.phase) or developmentState and ("local " .. developmentState.phase .. " round " ..
            developmentState.round .. "/" .. developmentState.rounds) or "no local test contest"
        say(localStatus .. "; raid leader: " .. (p.leader or "none") ..
            "; session: " .. (p.sessionId or "none") .. " v" .. (p.version or 0) ..
            "; lobby: " .. (p.lobbyState or "unavailable") .. "; last reject: " .. (p.lastRejected or "none"))
    elseif input == "announce winners" or input:match("^announce winners%s") then
        local ok,reason=announceWinners(input:sub(#"announce winners"+1))
        if not ok then say(reason) end
    elseif input == "devstart" then
        developmentState = Core.New(UnitName("player"), 1)
        say("Created a local test session. Multiplayer controls are unaffected.")
    elseif input == "devnetstart" then
        if practice then say("Exit solo practice before opening raid registration."); return end
        local ok, reason = run(openRegistration)
        say(ok and "Raid discovery queued." or ("Raid discovery: " .. reason))
    else
        say("Commands: /syb, /syb practice, /syb teampractice, /syb status, /syb devstart, /syb devnetstart")
    end
end
