local addonName, ns = ...
local Core, Network, UI = ns.Core, ns.Network, ns.UI
local frame = CreateFrame("Frame")
local state, developmentState, network
local roleRequest, notice
local practice, practiceCounter
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
    }, { onEvent=onNetworkEvent, onCommand=onNetworkCommand, chooseTheme=chooseAlphaTheme })
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

local function practiceView()
    local c = practice.contest
    return {practice=true, isLeader=true, sessionId=practice.id, phase=c.phase,
        contestants=#demoNames, spectators=0, pendingResponses=0, members=practice.members,
        lobbyState="ready_to_start", discoveryComplete=true, preparation=practice.preparation,
        runway=Core.RunwayStatus(c), runwayOrder=c.order, notice=notice}
end

local function enterPractice()
    if grouped() then return false, "practice_solo_only" end
    if not practice then
        practiceCounter = (practiceCounter or 0) + 1
        local c = Core.New("Practice host", 1)
        local members = {}
        for _, name in ipairs(demoNames) do
            assert(Core.Register(c, name, "contestant"))
            members[#members+1] = {name=name,guid=name,presence="addon_ready",role="contestant"}
        end
        practice = {id="practice-" .. practiceCounter, contest=c, members=members}
    end
    notice = nil
    UI.Show()
    return true
end

local function leavePractice()
    practice, notice = nil, nil
    UI.Refresh()
end

local function practiceAction(action)
    if not practice or grouped() then return false, "practice_solo_only" end
    local c = practice.contest
    if action == "START" then
        local ok, reason = Core.Start(c, Core.Shuffle(demoNames, math.random), 0)
        if not ok then return false,reason end
        practice.preparation = {theme=chooseAlphaTheme(),endsAt=GetServerTime()+Network.PREPARATION_SECONDS}
        return true
    end
    if action == "BEGIN_RUNWAY" then
        if not practice.preparation or GetServerTime()<practice.preparation.endsAt then return false,"preparation_running" end
        return Core.BeginRunway(c)
    end
    if action == "ADVANCE" then return Core.AdvanceRunway(c) end
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
    if p.isLeader and state and p.runway then p.runwayOrder = state.order end
    p.notice = notice
    if not p.localRole and pending and pending.status == "pending" then
        p.submittedRole = pending.message.role
        p.awaiting = GetTime() - roleRequest.sent < 6
        p.timedOut = not p.awaiting
    end
    return p
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
            getProjection=view, refresh=refresh, preferences=SYBCharacterDB.preferences,
            serverNow=GetServerTime, preparationSeconds=Network.PREPARATION_SECONDS,
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
