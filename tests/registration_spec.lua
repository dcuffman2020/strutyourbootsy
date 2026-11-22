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
function methods:SetNormalTexture(path) self.normalTexture = path end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetText(value)
    self.text = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return rawget(self,"text") or "" end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetHeight(h) self.height=h end
function methods:SetWidth(w) self.width=w end
function methods:SetWordWrap(wrap)
    assert(type(wrap)=="boolean", "SetWordWrap expects a boolean, not "..type(wrap))
    self.wordWrap=wrap
end
function methods:SetPoint(...) self.anchor={...} end
function methods:SetBackdropColor(...) self.fill={...} end
function methods:SetTextColor(...) self.textColor={...} end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:EnableMouse(value) self.mouse=value end
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
function methods:CreateTexture() return widget(self) end
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
    env.math = setmetatable({random=function(lo,hi)
        if lo then
            client.emoteDraws=(client.emoteDraws or 0)+1
            return client.reverseEmoteDraw and hi or lo
        end
        return (index or 0) / 10
    end}, {__index=math})
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
    client.emotes,client.warnings={},{}
    env.C_ChatInfo = {
        SendChatMessage=function(message,channel)
            if client.blockWarning then return false end
            assert(client.inRaid and index==1 and channel=="RAID_WARNING")
            client.warnings[#client.warnings+1]=message
        end,
        PerformEmote=function(token)
            if client.blockEmote then return false end
            client.emotes[#client.emotes+1]=token
            return true
        end,
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
    client.find = function(text)
        for _, frame in ipairs(client.frames) do
            local visible,ancestor=true,frame
            while ancestor do
                if ancestor.shown==false then visible=false;break end
                ancestor=rawget(ancestor,"parent")
            end
            if visible and frame.text == text then
                return frame
            end
        end
        return false
    end
    client.click = function(text)
        local frame=client.find(text)
        if not frame or frame.enabled~=true or not frame.scripts.OnClick or rawget(frame,"mouse")==false then return false end
        frame.scripts.OnClick(frame)
        return true
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
assert(solo.env.SYBMinimapLauncher.normalTexture == "Interface\\AddOns\\StrutYourBootsy\\Assets\\BootsyMinimap.tga")
local icon = assert(io.open("Assets/BootsyMinimap.tga", "rb"))
local bytes = icon:read("*a")
icon:close()
assert(#bytes == 18 + 64 * 64 * 4 and bytes:byte(3) == 2)
assert(bytes:byte(13) == 64 and bytes:byte(15) == 64 and bytes:byte(17) == 32 and bytes:byte(18) == 8)
assert(bytes:byte(22) == 0 and bytes:byte(22 + (64 * 32 + 32) * 4) > 245)
for _,asset in ipairs({"ArmoryClose","ArmoryTrim","ArmoryStarOn","ArmoryStarOff"}) do
    local f=assert(io.open("Assets/"..asset..".tga","rb"))
    local b=f:read("*a");f:close()
    assert(b:byte(3)==2 and b:byte(17)==32 and #b==18+b:byte(13)*b:byte(15)*4)
end

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

local function assertActivePhase(client, text)
    for _,frame in ipairs(client.frames) do
        for _,caption in ipairs(rawget(frame,"labels") or {}) do
            if caption:GetText()==text then
                assert(frame.border[1]==212/255 and frame.border[2]==173/255 and frame.border[3]==98/255,
                    "Active phase must keep the gold border")
                return
            end
        end
    end
    error("Missing unprefixed active phase: "..text)
end

local function assertFill(client,label,r,g,b)
    local row=assert(client.find(label),"Missing visible result: "..label)
    assert(row.fill[1]==r/255 and row.fill[2]==g/255 and row.fill[3]==b/255,
        "Incorrect result color for "..label)
    if r>150 or r==134 then
        assert(row.caption.textColor[1]==(r==134 and 1 or 14/255), "Metallic row text should contrast with its fill")
    end
end

local function assertEmoteGrid(client)
    local drawer=assert(client.find("Bow")).parent
    local labels,seen,rows={},{},{}
    for _,control in ipairs(client.frames) do
        if rawget(control,"parent")==drawer and control.shown then
            local name=control:GetText()
            local x,y=control.anchor[2],control.anchor[3]
            assert(name~="" and not seen[name], "Duplicate or empty emote button")
            assert(x>=0 and x+control.width<=drawer.width and -y+control.height<=drawer.height)
            assert(x==14+((#labels)%5)*72)
            seen[name]=true
            labels[#labels+1]=name
            rows[y]=(rows[y] or 0)+1
        end
    end
    assert(#labels==20 and drawer.parent.height==200 and client.env.SYBAdminWindow.height==589)
    assert(rows[-6]==5 and rows[-31]==5 and rows[-56]==5 and rows[-81]==5)
    assert(table.concat(labels,",",1,5)=="Bow,Wave,Dance,Flex,Chicken")
    return labels
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
assert(#leader.warnings==1 and leader.warnings[1]=="Strut Your Bootsy: Registration is open. Use /syb to join.")
leader.slash("announce winners Player3 Player4 Player5")
assert(#leader.warnings==1)
deliver()
for i = 2, 6 do
    advance(6)
    assert(not leader.click("Start contest"))
    assert(group[i].click("Contestant") and group[i].click("Confirm role"))
    deliver()
    if group[i].click("Confirm role") then deliver() end
end
status(leader, "lobby: ready_to_start")
assert(not group[2].click("Theme...") and not group[2].click("Runway timer"))
assert(leader.click("Theme..."))
local input=leader.env.SYBThemeInput
assert(not leader.click("Use theme"))
input:SetText("|c Untrusted")
assert(not leader.click("Use theme"))
input:SetText("  Guild-Forged, Round 1  ")
assert(leader.click("Use theme"))
assertLabel(leader,"Theme selected, hidden until Start: Guild-Forged, Round 1")
assert(leader.click("Runway timer") and leader.click("2:00"))
assert(leader.click("Runway timer") and leader.click("1:00"))
checkHiddenTheme = false
local finishingAt = group[1].env.GetServerTime() + 120
group[6].missReveal = true
assert(leader.click("Start contest"))
assert(leader.warnings[2]=="Strut Your Bootsy: Preparation is open. Theme: Guild-Forged, Round 1.")
deliver()
for i = 1, 5 do
    assertLabel(group[i], "Theme: Guild-Forged, Round 1")
    assertLabel(group[i], "Time to prepare: 2:00")
end
assertLabel(group[6], "Choose your role")
advance(24) -- delayed WELCOME recovery must not restart the timer.
for i, member in ipairs(group) do
    assertLabel(member, "Round 1 of 1: Preparation")
    assertLabel(member, "Registration is closed.\nYour role: " .. (i == 1 and "Administrator" or "Contestant"))
    assertLabel(member, "Theme: Guild-Forged, Round 1")
    assertLabel(member, "Time to prepare: 1:36")
    assert(not member.click("Start contest"))
    assert(not member.click("Begin runway"))
    assert(not member.click("Skip countdown"))
    assert(not member.click("Confirm role"))
end
advance(finishingAt - leader.env.GetServerTime() - 1)
for _, member in ipairs(group) do assertLabel(member, "Time to prepare: 0:01") end
-- At expiry only the raid leader may enter the runway. An unavailable
-- contestant holds the transition instead of silently losing their turn.
roster[4].online = false
leader.event("GROUP_ROSTER_UPDATE")
advance(1)
assert(not leader.click("Begin runway"))
assertLabel(leader, "A contestant is unavailable. Wait for them to return.")
roster[4].online = true
leader.event("GROUP_ROSTER_UPDATE")
for i=2,6 do assert(not group[i].click("Begin runway")) end
group[6].missReveal = false
assert(leader.click("Begin runway")); deliver()
assert(leader.warnings[3]=="Strut Your Bootsy: The runway has begun.")
for _,member in ipairs(group) do assertLabel(member,"Turn 1:00") end
advance(60)
for _,member in ipairs(group) do
    assertLabel(member,"Time’s up")
    assertLabel(member,"Presenting  1 of 5") -- Expiry never advances.
end
local order = {"Player3-Realm","Player4-Realm","Player5-Realm","Player6-Realm","Player2-Realm"}
for j,name in ipairs(order) do
    if j > 1 then advance(6) end
    local upNext = order[j+1] and "Up next: " .. order[j+1] or "Final presentation"
    for i,member in ipairs(group) do
        assertLabel(member, "Round 1 of 1: Runway")
        assertLabel(member,("Presenting  %d of 5"):format(j))
        assertLabel(member,name)
        assertLabel(member,upNext)
        if i>1 then assert(not member.click("Next contestant") and not member.click("Finish runway")) end
    end
    if j==1 then
        local presenter=group[3]
        for i,member in ipairs(group) do
            if i~=3 then assert(not member.click("Emotes +") and not member.click("Bow")) end
        end
        assert(presenter.click("Emotes +") and presenter.click("Bow"))
        assert(presenter.emotes[1]=="BOW" and #presenter.emotes==1)
        assertLabel(presenter,"Performed Bow.")
        local choices=assertEmoteGrid(presenter)
        assert(presenter.click(choices[6]) and presenter.emotes[2]==choices[6]:upper())
        assert(#presenter.emotes==2)
        presenter.blockEmote=true
        assert(presenter.click("Chicken") and #presenter.emotes==2)
        assertLabel(presenter,"Emote unavailable. Try your usual chat command.")
        presenter.blockEmote=false
        roster[3].online=false; leader.event("GROUP_ROSTER_UPDATE")
        assert(not leader.click("Next contestant"))
        roster[3].online=true; leader.event("GROUP_ROSTER_UPDATE")
        group[6].missReveal=true -- miss this turn update; recover via refresh below.
    end
    assert(leader.click(j==5 and "Finish runway" or "Next contestant")); deliver()
    assert(#leader.warnings==(j==5 and 4 or 3))
    if j==1 then
        assert(not group[3].click("Emotes +") and not group[3].click("Chicken"))
        assertLabel(group[6],"Presenting  1 of 5")
        assertLabel(group[6],"Player3-Realm")
        group[6].missReveal=false
        advance(5)
        assert(group[6].click("Refresh")); deliver()
        assertLabel(group[6],"Turn 0:55")
        assertLabel(group[6],"Presenting  2 of 5")
    end
end
for _,member in ipairs(group) do
    assertLabel(member, "Runway complete")
    assertLabel(member, "5 of 5 contestants presented.")
    assert(not member.click("Next contestant") and not member.click("Begin voting"))
end
leader.slash("practice")
assert(leader.chat[#leader.chat]:find("Leave your party or raid",1,true))

-- Exercise the public solo launcher and five-step loop. No raid packets may leave.
assert(leader.warnings[4]=="Strut Your Bootsy: The runway is complete.")
group[2].slash("announce winners Player3 Player4 Player5")
assert(#group[2].warnings==0)
leader.slash("announce winners Player3 Player3 Player5")
leader.slash("announce winners Player3 Player9 Player5")
assert(#leader.warnings==4)
leader.blockWarning=true
leader.slash("announce winners Player3 Player4 Player5")
assert(#leader.warnings==4)
leader.blockWarning=false
leader.slash("announce winners Player3 Player4 Player5")
leader.slash("announce winners Player4 Player3 Player5")
assert(#leader.warnings==5 and leader.warnings[5]=="Congratulations to Player3-Realm Player4-Realm Player5-Realm!")
roster, clients, packets = {}, {}, {}
local demo = makeClient()
demo.event("PLAYER_LOGIN")
demo.slash("practice")
assertLabel(demo,"PRACTICE MODE  /  FICTIONAL ROSTER")
assertActivePhase(demo,"Setup / Lobby")
assertLabel(demo, "Five fictional contestants. No raid messages are sent.")
assert(demo.click("Options"))
assertLabel(demo,"Interface preferences")
assert(demo.click("High contrast: Off") and demo.click("Save preferences"))
assert(demo.env.SYBCharacterDB.preferences.highContrast==true)
local setup=assert(demo.find("Setup Contest"))
assert(setup.anchor[3]=="BOTTOMLEFT" and setup.anchor[5]==48 and setup.caption.width==128)
assert(demo.click("Setup Contest") and demo.click("5") and demo.click("Cancel"))
assert(demo.click("Setup Contest"))
assert(demo.click("1"))
assertLabel(demo,"How many rounds?")
assertLabel(demo,"Setup · 1 of 5\nYour contest will have 1 round.")
assert(demo.click("2"))
assertLabel(demo,"Setup · 1 of 5\nYour contest will have 2 rounds.")
assert(demo.find("2").selected and not demo.find("1").selected)
assert(demo.click("Continue"))
assertLabel(demo,"Choose themes")
assert(demo.click("Custom theme"))
demo.env.SYBThemeInput:SetText("Midnight Masquerade")
assert(demo.click("Use theme"))
local custom=assert(demo.find("Custom theme: Midnight Masquerade"))
assert(custom.selected and custom.caption.wordWrap==true and custom.anchor[3] > demo.find("Random").anchor[3])
assert(not demo.find("Selected: Random"))
assert(demo.click("Custom theme: Midnight Masquerade") and demo.env.SYBThemeInput:GetText()=="Midnight Masquerade")
demo.env.SYBThemeInput:SetText(string.rep("W",48))
assert(demo.click("Use theme"))
assert(demo.find("Custom theme: "..string.rep("W",48)).selected)
assert(demo.click("Edit theme"))
demo.env.SYBThemeInput:SetText("Midnight Masquerade")
assert(demo.click("Use theme"))
assert(demo.click("Continue") and demo.click("3:00") and demo.click("Continue"))
assert(demo.click("0:30") and demo.click("Continue") and demo.click("Return to lobby"))
assert(demo.click("View as") and demo.click("Valeweaver"))
assertLabel(demo,"CONTESTANT VIEW  /  Valeweaver")
assertLabel(demo,"You’re registered as a contestant. Waiting for the raid leader.")
assert(not demo.click("Start contest") and not demo.click("Theme..."))
assert(demo.click("Host view") and demo.click("Start contest"))
assertLabel(demo,"Round 1 of 2: Preparation")
assertActivePhase(demo,"Preparation")
assertLabel(demo,"Theme: Midnight Masquerade")
assert(demo.click("View as"))
for _,name in ipairs({"Cinderstep","Valeweaver","Mossmantle","Copperwink","Thistledawn"}) do
    local option=assert(demo.find(name),"Missing visible practice contestant: "..name)
    assert(option.enabled and option.caption.wordWrap==false)
end
assert(demo.find("Back") and not demo.find("Begin runway"))
assert(demo.click("Valeweaver"))
assertLabel(demo,"Registration is closed.\nYour role: Contestant")
assertLabel(demo,"Time to prepare: 3:00")
assert(not demo.click("Skip countdown") and not demo.click("Begin runway"))
assert(demo.click("Host view"))
assertLabel(demo, "Time to prepare: 3:00")
assert(not demo.click("Begin runway"))
assert(demo.click("Skip countdown") and demo.click("Begin runway"))
for j,name in ipairs({"Valeweaver","Mossmantle","Copperwink","Thistledawn","Cinderstep"}) do
    assertLabel(demo,"Round 1 of 2: Runway")
    assertActivePhase(demo,"Runway")
    if j==1 then
        assertLabel(demo,"Turn 2:00")
        assert(demo.click("View as") and demo.click("Valeweaver"))
        assertLabel(demo,"You’re presenting now.")
        assert(demo.click("Emotes +"))
        local choices=assertEmoteGrid(demo)
        assert(demo.emoteDraws==15 and #demo.emotes==0)
        assert(demo.click(choices[6]))
        assertLabel(demo,"Practice: "..choices[6].." selected. Nothing was sent to WoW.")
        assert(#demo.emotes==0)
        assert(demo.click("Emotes −") and not demo.click("Chicken"))
        assert(demo.env.SYBAdminWindow.height==564)
        assert(demo.click("Emotes +"))
        assert(table.concat(choices)==table.concat(assertEmoteGrid(demo)) and demo.emoteDraws==15)
        assert(demo.click("Host view") and not demo.click("Emotes +"))
        assert(demo.click("View as") and demo.click("Mossmantle"))
        assert(not demo.click("Emotes +"))
        assert(demo.click("Host view") and demo.click("View as") and demo.click("Valeweaver"))
        assertLabel(demo,"Up next: Mossmantle")
        assert(not demo.click("Next contestant") and not demo.click("Pause"))
        assert(demo.click("Host view"))
        now=now+15
        local w=demo.env.SYBAdminWindow
        w.scripts.OnUpdate(w,15)
        assertLabel(demo,"Turn 1:45")
        assert(demo.click("Pause"));assertLabel(demo,"Runway paused")
        assert(not demo.click("Next contestant"))
        now=now+30
        assert(demo.click("Resume runway"));assertLabel(demo,"Presenting  1 of 5")
        assertLabel(demo,"Turn 1:45")
    elseif j==2 then
        demo.reverseEmoteDraw=true
        assert(demo.click("View as") and demo.click("Mossmantle") and demo.click("Emotes +"))
        assert(demo.emoteDraws==30 and assertEmoteGrid(demo)[6]=="Yawn")
        assert(#demo.emotes==0 and demo.click("Host view"))
    end
    local found=false
    for _,f in ipairs(demo.frames) do if rawget(f,"text")==name .. "  ·  Presenting" and f.shown then found=true end end
    assert(found,"Missing exact solo presenter: " .. name)
    assert(demo.click(j==5 and "Finish runway" or "Next contestant"))
end
assertLabel(demo, "Runway complete")
local function rate(name,rating)
    for _,f in ipairs(demo.frames) do
        if rawget(f,"ratedName")==name and rawget(f,"rating")==rating and f.shown and f.enabled then
            f.scripts.OnClick(f)
            return true
        end
    end
    return false
end
for round=1,2 do
    assert(demo.click("Begin voting"))
    assertLabel(demo,"Judge contestants")
    assert(not demo.click("Submit ballot") and not rate("Cinderstep",5))
    assert(rate("Valeweaver",5) and rate("Mossmantle",4) and rate("Copperwink",3) and rate("Thistledawn",2))
    assert(demo.click("Submit ballot"))
    assertLabel(demo,"Ballot submitted")
    assert(not rate("Valeweaver",4))
    assert(demo.click("Skip vote timer") and demo.click("View round results"))
    assertLabel(demo,"Round results")
    assertFill(demo,"1st place · Valeweaver · 5.0 / 5",212,173,98)
    assertFill(demo,"2nd place · Mossmantle · 4.0 / 5",188,201,213)
    assertFill(demo,"3rd place · Copperwink · 3.0 / 5",134,102,56)
    assertFill(demo,"Cinderstep · Not rated",21,31,42)
    if round==1 then
        assert(demo.click("Begin round 2") and demo.click("Skip countdown") and demo.click("Begin runway"))
        for _=1,4 do assert(demo.click("Next contestant")) end
        assert(demo.click("Finish runway"))
    end
end
assert(demo.click("Final awards"))
assertLabel(demo,"Final awards")
assertFill(demo,"1st place · Not revealed",21,31,42)
assertFill(demo,"2nd place · Not revealed",21,31,42)
assertFill(demo,"3rd place · Not revealed",21,31,42)
assert(demo.click("Next reveal"))
assertFill(demo,"3rd place · Copperwink",134,102,56)
assert(demo.click("Next reveal"))
assertFill(demo,"2nd place · Mossmantle",188,201,213)
assert(demo.click("Next reveal"))
assertFill(demo,"1st place · Valeweaver",212,173,98)
assertFill(demo,"Honorable mention · Thistledawn",21,31,42)
local localWarnings=0
for _,line in ipairs(demo.chat) do
    if line:find("[Practice Raid Warning]",1,true) then localWarnings=localWarnings+1 end
end
assert(localWarnings==12 and #demo.warnings==0)
assert(demo.chat[#demo.chat]:find("Congratulations to Valeweaver Mossmantle Copperwink!",1,true))
assert(demo.click("Practice again"))
assertLabel(demo,"Registration lobby")
demo.slash("devnetstart")
assert(demo.chat[#demo.chat]:find("Exit solo practice",1,true))
assert(demo.click("Exit practice"))
assertLabel(demo, "Welcome to the runway")
assert(#packets==0,"Solo practice must not send addon messages")
demo.slash("practice")
demo.inRaid=true; demo.event("GROUP_ROSTER_UPDATE")
assertLabel(demo, "Welcome to the runway")
assert(#packets==0)
demo.ns.UI.Initialize({getProjection=function()
    return {practice=true,isLeader=true,sessionId="ties",phase="round_results",round=1,rounds=1,
        result={{name="Copperwink",average=5},{name="Valeweaver",average=5},{name="Mossmantle",average=4},
            {name="Thistledawn",average=2},{name="Cinderstep"}}}
end})
demo.ns.UI.Show()
assertFill(demo,"Tied for 1st place · Copperwink · 5.0 / 5",212,173,98)
assertFill(demo,"Tied for 1st place · Valeweaver · 5.0 / 5",212,173,98)
assertFill(demo,"3rd place · Mossmantle · 4.0 / 5",134,102,56)
assertFill(demo,"Cinderstep · Not rated",21,31,42)
print("Registration, contestant preview, emote grid, and medal colors passed")
