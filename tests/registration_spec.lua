-- Load the real TOC in isolated mock WoW clients with a shared transport.
local now = 100
local roster, clients, packets = {}, {}, {}
local addon = "StrutYourBootsy"
local checkHiddenTheme = false
for i = 1, 8 do
    roster[i] = {name="Player" .. i, guid="GUID-" .. i, online=true}
end

local methods = {}
local widgets = {__index=function(_, key)
    return methods[key] or function() end
end}
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetText(value) self.text = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:Show() self.shown = true end
function methods:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:SetShown(value) self.shown = value end
function methods:GetWidth() return 140 end
function methods:GetHeight() return 140 end
function methods:GetCenter() return 100, 100 end
function methods:GetEffectiveScale() return 1 end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
local function widget(parent)
    return setmetatable({scripts={}, events={}, parent=parent, shown=true, enabled=true}, widgets)
end
function methods:CreateFontString()
    local label = widget(self)
    self.labels = rawget(self, "labels") or {}
    self.labels[#self.labels + 1] = label
    return label
end

local function makeClient(index)
    local character = index and roster[index] or {name="Solo", guid="Solo"}
    local client = {frames={}, chat={}, timers={}, index=index, inRaid=index ~= nil}
    local env = setmetatable({}, {__index=_G})
    client.env = env
    env.CreateFrame = function(_, name, parent)
        local frame = widget(parent)
        client.frames[#client.frames + 1] = frame
        if name then env[name] = frame end
        return frame
    end
    env.UIParent, env.Minimap, env.GameTooltip = widget(), widget(), widget()
    env.UISpecialFrames, env.SlashCmdList = {}, {}
    env.GameTooltip_Hide = function() end
    env.STANDARD_TEXT_FONT = "Font"
    env.DEFAULT_CHAT_FRAME = {AddMessage=function(_, text) client.chat[#client.chat + 1] = text end}
    env.math = setmetatable({random=function() return (index or 0) / 10 end}, {__index=math})
    env.GetTime, env.GetServerTime = function() return now end, function() return 1700000000 + now end
    env.GetCursorPosition = function() return 180, 110 end
    env.GetNormalizedRealmName = function() return "Realm" end
    env.UnitName = function() return character.name end
    env.IsInRaid = function() return client.inRaid end
    env.GetNumGroupMembers = function() return #roster end
    local function unitRow(unit)
        return unit == "player" and character or roster[tonumber(unit:match("%d+"))]
    end
    env.UnitFullName = function(unit) return unitRow(unit).name, "" end
    env.UnitGUID = function(unit) return unitRow(unit).guid end
    env.GetRaidRosterInfo = function(i)
        return roster[i].name, i == 1 and 2 or 0, nil, nil, nil, nil, nil, roster[i].online
    end
    env.C_Timer = {After=function(seconds, fn)
        client.timers[#client.timers + 1] = {due=now+seconds, run=fn}
    end}
    env.Enum = {SendAddonMessageResult={Success=0}}
    local registered = false
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix=function() registered = not client.failPrefix; return registered and 0 or 1 end,
        IsAddonMessagePrefixRegistered=function() return registered end,
        SendAddonMessage=function(prefix, wire, channel, target)
            if client.failSend then return 1 end
            if checkHiddenTheme then
                assert(not wire:find("|theme=", 1, true) and not wire:find("|prep_ends=", 1, true),
                    "theme or deadline leaked during registration")
            end
            packets[#packets + 1] = {prefix, wire, channel, target, character.name .. "-Realm"}
            return 0
        end,
    }
    local namespace = {}
    client.ns = namespace
    local files = {}
    for line in io.lines(addon .. ".toc") do
        if line:match("%.lua$") then
            files[#files + 1] = line
            local chunk = assert(loadfile(line, "t", env))
            if setfenv then setfenv(chunk, env) end
            chunk(addon, namespace)
        end
    end
    assert(table.concat(files, ",") == "Core.lua,Network.lua,UI.lua,Main.lua")
    client.event = function(event, ...)
        local frame = client.frames[1]
        if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
    end
    client.slash = env.SlashCmdList.STRUTYOURBOOTSY
    client.click = function(text)
        for _, frame in ipairs(client.frames) do
            if frame.text == text and frame.enabled == true and frame.shown == true then
                frame.scripts.OnClick(frame)
                return true
            end
        end
        return false
    end
    if index then clients[character.name .. "-Realm"] = client end
    return client
end

local function deliver()
    local count = 0
    while #packets > 0 do
        count = count + 1
        assert(count < 150, "transport feedback loop")
        local packet = table.remove(packets, 1)
        for name, recipient in pairs(clients) do
            if (packet[3] == "RAID" or packet[4] == name) and
               not (recipient.missReveal and packet[3] == "RAID" and packet[2]:find("t=STATE", 1, true)) then
                recipient.event("CHAT_MSG_ADDON", packet[1], packet[2], packet[3], packet[5])
            end
        end
    end
end

local function advance(seconds)
    now = now + seconds
    for _, client in pairs(clients) do
        local previous = client.timers
        client.timers = {}
        local w = client.env.SYBAdminWindow
        if w and w:IsShown() and w.scripts.OnUpdate then w.scripts.OnUpdate(w, seconds) end
        for _, timer in ipairs(previous) do
            if timer.due <= now then timer.run()
            else client.timers[#client.timers + 1] = timer end
        end
    end
    deliver()
end

local function status(client, text)
    client.slash(" STATUS ")
    assert(client.chat[#client.chat]:find(text, 1, true), client.chat[#client.chat])
end

local solo = makeClient()
solo.failPrefix = true
solo.event("PLAYER_LOGIN")
assert(not solo.frames[1].events.CHAT_MSG_ADDON)
assert(solo.env.SLASH_STRUTYOURBOOTSY1 == "/syb")
assert(solo.env.SYBMinimapLauncher.parent == solo.env.Minimap)
solo.slash("")
local window = solo.env.SYBAdminWindow
assert(window:IsShown() and solo.env.UISpecialFrames[1] == "SYBAdminWindow")
window.scripts.OnDragStart(window)
assert(window.moving)
window.scripts.OnDragStop(window)
assert(not window.moving)
solo.slash("")
assert(not window:IsShown())
local launcher = solo.env.SYBMinimapLauncher
launcher.scripts.OnClick(launcher)
assert(window:IsShown())
launcher.scripts.OnDragStart(launcher)
launcher.scripts.OnUpdate(launcher)
launcher.scripts.OnDragStop(launcher)
assert(type(solo.env.SYBCharacterDB.preferences.launcherAngle) == "number")
assert(launcher.scripts.OnUpdate == nil)
solo.slash("devstart")
status(solo, "local registration round 0/1")
solo.failPrefix = false
solo.slash("devnetstart")
assert(solo.frames[1].events.CHAT_MSG_ADDON)
assert(solo.chat[#solo.chat]:find("not_raid_leader", 1, true))

local function assertLabel(client, text)
    for _, frame in ipairs(client.frames) do
        for _, label in ipairs(rawget(frame, "labels") or {}) do
            if rawget(label, "text") == text then return end
        end
    end
    error("Missing UI label: " .. text)
end

-- A previous transport error must not conceal today's Start blocker.
solo.ns.UI.Initialize({getProjection=function()
    return {sessionId="mock", phase="registration", isLeader=true, members={},
        contestants=5, spectators=0, pendingResponses=0,
        lobbyState="discovery_pending", notice="transport_failed"}
end})
solo.ns.UI.Refresh()
assertLabel(solo, "Discovery is running. Give raid members time to respond.")
assertLabel(solo, "The game rejected the message. Check your raid connection and retry.")
assert(not solo.click("Start contest"))

local group = {}
for i = 1, 7 do group[i] = makeClient(i); group[i].event("PLAYER_LOGIN"); group[i].slash("") end
local leader = group[1]
assert(leader.click("Open registration"))
deliver()
status(group[2], " v1;")
assert(not leader.click("Contestant"))
assert(not leader.click("Start contest"))

-- Non-success result from WoW must leave the role selectable.
group[2].failSend = true
assert(group[2].click("Contestant") and group[2].click("Confirm role"))
assert(group[2].click("Confirm role"))
group[2].failSend = false

for i = 2, 6 do
    advance(6)
    local member = group[i]
    if i ~= 2 then assert(member.click("Contestant")) end
    assert(member.click("Confirm role"))
    local registration = packets[#packets]
    assert(not member.click("Confirm role"))
    deliver()
    -- A concurrent stale request has to resync before resubmitting.
    if member.click("Confirm role") then
        deliver()
    end
    assert(not member.click("Confirm role"))
    if i == 2 then
        leader.event("CHAT_MSG_ADDON", registration[1], registration[2], registration[3], registration[5])
        deliver()
        status(leader, " v2;")
    end
end
status(leader, "pending_addon_users")
assert(not leader.click("Start contest"))

advance(6)
assert(group[7].click("Spectator") and group[7].click("Confirm role"))
deliver()
if group[7].click("Confirm role") then deliver() end
assert(not leader.click("Start contest"))
assert(leader.click("Player8-Realm  Unconfirmed"))
assert(leader.click("Confirm no addon"))
status(leader, "ready_to_start")

roster[2].online = false
leader.event("GROUP_ROSTER_UPDATE")
assert(not leader.click("Start contest"))
roster[2].online = true
leader.event("GROUP_ROSTER_UPDATE")
assert(leader.click("Start contest"))
advance(16)
status(leader, " v8;")
status(group[2], " v8;")
assert(not group[2].click("Confirm role"))
roster[9] = {name="Player9", guid="GUID-9", online=true}
local late = makeClient(9)
late.event("PLAYER_LOGIN")
late.event("PLAYER_ENTERING_WORLD")
late.slash("")
advance(6)
status(late, "late_joiner")
assertLabel(late, "Theme: Royalty")
assertLabel(late, "Registration is closed.\nYour role: Observer")
assert(not late.click("Confirm role"))
-- Re-create the reported raid size exactly: current leader and five contestants,
-- with no spectator or passive-observer row.
roster, clients, packets = {}, {}, {}
for i = 1, 6 do roster[i] = {name="Player" .. i, guid="GUID-" .. i, online=true} end
group = {}
for i = 1, 6 do
    group[i] = makeClient(i)
    group[i].event("PLAYER_LOGIN")
    group[i].slash("")
end
leader = group[1]
checkHiddenTheme = true
assert(leader.click("Open registration"))
deliver()
for i = 2, 6 do
    advance(6)
    assert(not leader.click("Start contest"))
    assert(group[i].click("Contestant") and group[i].click("Confirm role"))
    deliver()
    if group[i].click("Confirm role") then deliver() end
end
status(leader, "lobby: ready_to_start")
checkHiddenTheme = false
local finishingAt = group[1].env.GetServerTime() + 120
group[6].missReveal = true
assert(leader.click("Start contest"))
deliver()
for i = 1, 5 do
    assertLabel(group[i], "Theme: Royalty")
    assertLabel(group[i], "Time to prepare: 2:00")
end
assertLabel(group[6], "Choose your role")
advance(24) -- delayed WELCOME recovery must not restart the timer.
for i, member in ipairs(group) do
    assertLabel(member, "Round 1 of 1: Preparation")
    assertLabel(member, "Registration is closed.\nYour role: " .. (i == 1 and "Administrator" or "Contestant"))
    assertLabel(member, "Theme: Royalty")
    assertLabel(member, "Time to prepare: 1:36")
    assert(not member.click("Start contest"))
    assert(not member.click("Confirm role"))
end
advance(finishingAt - leader.env.GetServerTime() - 1)
for _, member in ipairs(group) do assertLabel(member, "Time to prepare: 0:01") end
advance(1)
advance(8)
for _, member in ipairs(group) do
    assertLabel(member, "Preparation complete. This alpha ends here.")
    assert(not member.click("Begin runway"))
end
print("Registration, theme reveal and preparation countdown spec passed")
