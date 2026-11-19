local addonName, ns = ...
local Core = ns.Core
local Network = ns.Network
local frame = CreateFrame("Frame")
local state

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aStrut Your Bootsy:|r " .. message)
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end
    SYBCharacterDB = SYBCharacterDB or { preferences = {} }
    say("Foundation + raid discovery loaded. /syb status or /syb peers")
end)

Network.SetCallback(function(event, value)
    if event == "PREFIX_FAILED" then say("Addon messaging prefix registration failed: " .. tostring(value))
    elseif event == "SEND_FAILED" then say("Discovery message not queued: " .. tostring(value))
    end
end)

SLASH_STRUTYOURBOOTSY1 = "/syb"
SlashCmdList.STRUTYOURBOOTSY = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "status" then
        if not state then say("No active local contest (multiplayer sessions not yet enabled).")
        else say("Local phase: " .. state.phase .. "; round: " .. state.round .. "/" .. state.rounds) end
    elseif input == "peers" then
        local roster,total,peers=Network.GetRoster(),0,0
        for _,member in pairs(roster) do
            total=total+1
            if member.addon then peers=peers+1 end
        end
        say("Raid roster: " .. total .. " members; " .. peers .. " addon peers confirmed (discovery only).")
    elseif input == "refresh" then
        Network.Refresh()
        say("Raid roster refreshed; discovery respects a 10-second send interval.")
    elseif input == "devstart" then
        -- Developer smoke test only: not a live raid session.
        local player = UnitName("player")
        state = Core.New(player, 1)
        say("Created a local test session. Multiplayer controls are not active.")
    else
        say("Commands: /syb status, /syb peers, /syb refresh, /syb devstart")
    end
end
