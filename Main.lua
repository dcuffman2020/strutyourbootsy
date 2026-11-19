local addonName, ns = ...
local Core = ns.Core
local Network = ns.Network
local frame = CreateFrame("Frame")
local state
local network

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aStrut Your Bootsy:|r " .. message)
end

local function playerName()
    local name, realm = UnitFullName("player")
    if not name then return nil end
    realm = (realm and realm ~= "" and realm) or
        (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    return Network.NormalizeName(name, realm)
end

local function localRealm()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
end

local function raidRoster()
    local rows = {}
    for index = 1, GetNumGroupMembers() do
        local name, rank, _, _, _, _, _, online = GetRaidRosterInfo(index)
        if name then
            rows[#rows + 1] = { name=name, guid=UnitGUID("raid" .. index), connected=online, leader=rank == 2 }
        end
    end
    return rows
end

local function onNetworkEvent(event, data)
    if event == "session_started" then
        state = Core.New(data.leader, 1)
    elseif event == "authority_changed" then
        say("Raid leadership changed; the development session was paused and ended.")
    elseif event == "command_rejected" and data.reason then
        say("Network command rejected: " .. data.reason)
    end
end

local function onNetworkCommand(action, sender, message)
    if action ~= "ROLE" then return false, "unsupported_command" end
    if not state then return false, "no_session" end
    return Core.Register(state, sender, message.role)
end

local function setupNetwork()
    if network then return true end
    network = Network.New({
        now=GetTime,
        playerName=playerName,
        localRealm=localRealm,
        getRoster=raidRoster,
        registerPrefix=function(prefix) return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end,
        send=function(prefix, message, channel, target)
            return pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
        end,
    }, { onEvent=onNetworkEvent, onCommand=onNetworkCommand })
    local ok, reason = network:Register()
    if not ok then say("Raid communications unavailable: " .. reason); return false end
    network:RefreshRoster()
    return true
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        SYBCharacterDB = SYBCharacterDB or { preferences = {} }
        if setupNetwork() then
            frame:RegisterEvent("CHAT_MSG_ADDON")
            frame:RegisterEvent("GROUP_ROSTER_UPDATE")
            frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        end
        say("Foundation loaded. /syb status")
    elseif event == "CHAT_MSG_ADDON" and network then
        local prefix, message, channel, sender = ...
        network:Receive(prefix, message, channel, sender)
    elseif (event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD") and network then
        network:RefreshRoster()
    end
end)

SLASH_STRUTYOURBOOTSY1 = "/syb"
SlashCmdList.STRUTYOURBOOTSY = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "status" then
        local localStatus = not state and "no local contest" or
            ("local " .. state.phase .. " round " .. state.round .. "/" .. state.rounds)
        if network then
            local p = network:GetProjection()
            say(localStatus .. "; raid leader: " .. (p.leader or "none") ..
                "; session: " .. (p.sessionId or "none") .. " v" .. p.version ..
                "; lobby: " .. p.lobbyState .. "; last reject: " .. (p.lastRejected or "none"))
        else say(localStatus .. "; raid communications unavailable") end
    elseif input == "devstart" then
        -- Developer smoke test only: not a live raid session.
        local player = UnitName("player")
        state = Core.New(player, 1)
        say("Created a local test session. Multiplayer controls are not active.")
    elseif input == "devnetstart" then
        if not setupNetwork() then return end
        network:RefreshRoster()
        local id = tostring(math.floor(GetServerTime())) .. "-" .. tostring(math.floor(GetTime() * 1000) % 100000)
        local ok, reason = network:StartSession(id)
        if not ok then say("Development raid session not started: " .. reason); return end
        local sent, delivery = network:BeginDiscovery()
        if sent and C_Timer and C_Timer.After then
            C_Timer.After(Network.DISCOVERY_SECONDS, function()
                if network then network:ClassifyDiscovery() end
            end)
        end
        say(sent and ("Development raid discovery queued (" .. delivery .. ").") or
            ("Development raid discovery failed: " .. delivery))
    else
        say("Commands: /syb status, /syb devstart (local test), /syb devnetstart (leader-only network smoke test)")
    end
end
