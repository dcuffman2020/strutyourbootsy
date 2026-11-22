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
-- Small one-round alpha pool; the full catalog and custom theme setup come later.
local alphaThemes = {"Royalty", "Out of This World", "Back from the Dead", "Heroes of Azeroth"}

local function chooseAlphaTheme()
    return alphaThemes[1 + math.floor(math.random() * #alphaThemes)]
end

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aStrut Your Bootsy:|r " .. message)
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

local function onNetworkEvent(event, data)
    if event == "session_started" then
        raidCustomTheme=nil
        state = Core.New(data.leader, 1)
        notice = nil
    elseif event == "authority_changed" then
        notice = "authority_changed"
    elseif event == "session_ended" and state then
        Core.End(state)
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
        for _, member in ipairs(projection.members) do
            if member.presence == "addon_ready" and member.role == "contestant" then
                order[#order + 1] = member.name
            end
        end
        return Core.Start(state, Core.Shuffle(order, math.random), projection.presence.addon_pending + projection.presence.unknown)
    end
    if action == "BEGIN_RUNWAY" or action == "ADVANCE" then
        local operation = action == "BEGIN_RUNWAY" and Core.BeginRunway or Core.AdvanceRunway
        local ok, reason = operation(state)
        return ok, reason, ok and Core.RunwayStatus(state) or nil
    end
    return false, "unsupported_command"
end

local function setupNetwork()
    if network then return true end
    local candidate = Network.New({
        now=GetTime, serverNow=GetServerTime, playerName=playerName, localRealm=localRealm, getRoster=raidRoster,
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
    }, { onEvent=onNetworkEvent, onCommand=onNetworkCommand, chooseTheme=function() return raidCustomTheme or chooseAlphaTheme() end })
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
    local ok, reason = network:StartSession(id)
    if not ok then return false, reason end
    local queued, delivery = network:BeginDiscovery()
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
    if c.phase == "round_results" then
        result={}
        for _,name in ipairs(c.order) do
            result[#result+1]={name=name, average=c.scores[c.round][name]}
        end
        table.sort(result,function(a,b)
            if a.average==b.average then return a.name<b.name end
            return (a.average or 0)>(b.average or 0)
        end)
    end
    return {practice=true,isLeader=true,sessionId=practice.id,phase=c.phase,round=c.round,rounds=c.rounds,
        contestants=#demoNames,spectators=0,pendingResponses=0,members=practice.members,
        lobbyState="ready_to_start",discoveryComplete=true,preparation=practice.preparation,prepLimit=practice.settings.prep,
        runway=turn,runwaySeconds=practice.runwaySeconds,runwayOrder=c.order,notice=notice,wizard=practice.wizard,
        settings=practice.wizardDraft or practice.settings,customTheme=(practice.wizardDraft or practice.settings).customTheme,ballot=practice.ballot,ballotSubmitted=practice.ballotSubmitted,
        voteEndsAt=practice.voteEndsAt,result=result,reveal=practice.reveal,revealCount=practice.revealCount,
        practiceVoter=practiceVoter,practicePaused=c.phase=="paused"}
end

local function enterPractice()
    if grouped() then return false,"practice_solo_only" end
    if not practice then
        practiceCounter=(practiceCounter or 0)+1
        local c=Core.New("Practice host",1)
        local members={}
        for _,name in ipairs(demoNames) do
            assert(Core.Register(c,name,"contestant"))
            members[#members+1]={name=name,guid=name,presence="addon_ready",role="contestant"}
        end
        practice={id="practice-"..practiceCounter,contest=c,members=members,ballot={},themePool={},
            settings={rounds=1,theme="Random",prep=120,vote=60},runwaySeconds=Network.RUNWAY_SECONDS}
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
                [3]={prep={60,120,180}},[4]={vote={30,60,90}}})[practice.wizard]
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
        local ok,reason=Core.Start(c,Core.Shuffle(demoNames,math.random),0)
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
        local ok,reason=Core.SubmitBallot(c,practiceVoter,practice.ballot)
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

local function view()
    if practice then return practiceView() end
    local p = network and network:GetProjection() or {}
    local pending = roleRequest and network and network.pending[roleRequest.id]
    if p.lobbyState == "ready_to_start" and state then
        local ready, reason = Core.CanStart(state, p.pendingResponses + p.presence.unknown)
        if not ready then p.lobbyState = reason end
    end
    if p.isLeader and p.phase=="registration" then p.customTheme=raidCustomTheme; p.runwaySeconds=network.runwaySeconds end
    if p.isLeader and state and p.runway then p.runwayOrder = state.order end
    p.notice = notice
    if not p.localRole and pending and pending.status == "pending" then
        p.submittedRole = pending.message.role
        p.awaiting = GetTime() - roleRequest.sent < 6
        p.timedOut = not p.awaiting
    end
    return p
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
    if practice then return practiceAction(action) end
    if not network then return false,"not_registered" end
    local ok, reason = network:AdminCommand(action,commandId())
    if not ok then return false,reason end
    local id, version = network.sessionId, network.version
    if not network:BroadcastContest() then
        C_Timer.After(Network.SEND_WINDOW + 0.25, function()
            if not practice and network.sessionId == id and network.version == version then network:BroadcastContest() end
        end)
    end
    return true
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        SYBCharacterDB = SYBCharacterDB or {preferences={}}
        SYBCharacterDB.preferences = SYBCharacterDB.preferences or {}
        setupNetwork()
        UI.Initialize({
            getProjection=view, playerName=playerName, refresh=refresh, preferences=SYBCharacterDB.preferences,
            serverNow=GetServerTime, preparationSeconds=Network.PREPARATION_SECONDS,
            normalizeTheme=Network.NormalizeCustomTheme,setCustomTheme=setCustomTheme,
            setRunwaySeconds=setRunwaySeconds,runwayOptions=Network.RUNWAY_OPTIONS,
            groupActive=grouped, enterPractice=function() run(enterPractice) end,
            practiceAction=function(...) run(practiceAction,...) end,
            skipVote=function()
                if practice and practice.contest.phase=="voting" then practice.voteEndsAt=GetServerTime(); UI.Refresh() end
            end,
            openRegistration=function() run(openRegistration) end,
            start=function() run(adminAction,"START") end,
            beginRunway=function() run(adminAction,"BEGIN_RUNWAY") end,
            advanceRunway=function() run(adminAction,"ADVANCE") end,
            leavePractice=leavePractice,
            restartPractice=function() leavePractice(); enterPractice() end,
            skipPreparation=function()
                if practice and practice.contest.phase=="preparation" and practice.preparation then
                    practice.preparation.endsAt=GetServerTime()
                    UI.Refresh()
                end
            end,
            cancel=function() run(function() return network:CancelRegistration() end) end,
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
    elseif input == "practice stop" then
        if practice then leavePractice(); say("Solo practice ended.") end
    elseif input == "status" then
        local p = view()
        local localStatus = p.practice and ("Practice mode: " .. p.phase) or developmentState and ("local " .. developmentState.phase .. " round " ..
            developmentState.round .. "/" .. developmentState.rounds) or "no local test contest"
        say(localStatus .. "; raid leader: " .. (p.leader or "none") ..
            "; session: " .. (p.sessionId or "none") .. " v" .. (p.version or 0) ..
            "; lobby: " .. (p.lobbyState or "unavailable") .. "; last reject: " .. (p.lastRejected or "none"))
    elseif input == "devstart" then
        developmentState = Core.New(UnitName("player"), 1)
        say("Created a local test session. Multiplayer controls are unaffected.")
    elseif input == "devnetstart" then
        if practice then say("Exit solo practice before opening raid registration."); return end
        local ok, reason = run(openRegistration)
        say(ok and "Raid discovery queued." or ("Raid discovery: " .. reason))
    else
        say("Commands: /syb, /syb practice, /syb status, /syb devstart, /syb devnetstart")
    end
end
