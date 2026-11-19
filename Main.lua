local addonName, ns = ...
local Core = ns.Core
local frame = CreateFrame("Frame")
local state

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aStrut Your Bootsy:|r " .. message)
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end
    SYBCharacterDB = SYBCharacterDB or { preferences = {} }
    say("Foundation loaded. /syb status")
end)

SLASH_STRUTYOURBOOTSY1 = "/syb"
SlashCmdList.STRUTYOURBOOTSY = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "status" then
        if not state then say("No active local contest (multiplayer not yet enabled).")
        else say("Local phase: " .. state.phase .. "; round: " .. state.round .. "/" .. state.rounds) end
    elseif input == "devstart" then
        -- Developer smoke test only: not a live raid session.
        local player = UnitName("player")
        state = Core.New(player, 1)
        say("Created a local test session. Multiplayer controls are not active.")
    else
        say("Commands: /syb status, /syb devstart (local test)")
    end
end
