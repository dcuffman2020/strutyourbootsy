local addonName, ns = ...
local UI = {}
ns.UI = UI

local window, launcher
local brand, title, summary, details, status, actionNotice, roleHint, list, listContent
local primary, secondary, contestant, spectator, confirmPassive, skipPrep, utility, prefsLink
local badge, windowHeader, overview, info, votePanel, endOfTimer, heroName, heroNext
local phases, choices, ratingRows = {}, {}, {}
local preferencesMode, draftPreferences
local voteDeadline, voteExpiry, voteSubmitted
local assetPath="Interface\\AddOns\\StrutYourBootsy\\Assets\\"
local prepLimit
local context = {}
local rows = {}
local selectedRole, selectedObserver, sessionId
local prepDeadline, prepSeconds, prepTick, prepHost, prepBlocked = nil, nil, 0, false, false
-- Tournament Armory semantic colors from the approved Figma components.
local function rgb(n) return {math.floor(n/65536)/255, math.floor(n/256)%256/255, n%256/255} end
local gold,pale,muted=rgb(0xD4AD62),rgb(0xF4EADD),rgb(0xBCC9D5)
local palette={window=rgb(0x0E151D),panel=rgb(0x151F2A),outline=rgb(0x435364),
    header=rgb(0x411628),cta=rgb(0x751E35),selected=rgb(0x352231),
    tag=rgb(0x222F3C),trim=rgb(0x866638),success=rgb(0xA9E7B7),info=rgb(0xC0DFFA)}
local labels={}
local themeNames={"Random","Royalty","Out of This World","Back from the Dead","Heroes of Azeroth"}
local unpackColor = unpack or table.unpack

local presenceLabels = {
    addon_ready="Registered", addon_pending="Pending role", unknown="Unconfirmed",
    no_addon="Passive (no addon)", late_joiner="Late joiner", disconnected="Disconnected",
}
local messages = {
    insufficient_contestants="Register at least five connected contestants.",
    pending_addon_users="Wait for pending roles and confirm any verified no-addon observers.",
    discovery_pending="Discovery is running. Give raid members time to respond.",
    not_raid_leader="Only the current raid leader can open registration or start.",
    disconnected="Check the raid roster and ask disconnected contestants to reconnect.",
    late_joiner="You joined after registration opened and can observe.",
    authority_changed="Raid leadership changed. The previous session ended.",
    snapshot_mismatch="The lobby changed. Wait for the refresh and confirm your role again.",
    transport_failed="The game rejected the message. Check your raid connection and retry.",
    rate_limited="Too many messages queued. Wait a few seconds and retry.",
    not_registered="Raid communications are unavailable. Reopen registration to retry.",
    wrong_phase="Registration is closed.",
    minimum_five_contestants="Register at least five connected contestants.",
    registration_pending="Wait for pending addon users to confirm their roles.",
    invalid_setting="Choose one of the listed options.",
    invalid_rating="Choose 1–5 stars for a contestant other than yourself.",
    empty_ballot="Choose at least one rating before submitting.",
    ballot_already_submitted="Your ballot has already been submitted.",
    voting_closed="Voting is closed or your ballot is already locked.",
    voting_running="Wait for voting to close before viewing results.",
    practice_tie="A podium tie remains. Tie resolution is not included in this build.",
    preparation_running="Wait for the preparation timer to finish.",
    practice_solo_only="Leave your party or raid to use solo practice.",
    preparation_unavailable="Could not start preparation. Try Start again.",
    invalid_runway_order="Roster and registrations differ. Check the roster or reopen registration.",
    already_registered="The leader already registered your role. Refresh to confirm it.",
    session_active="A raid session is already active.",
}

local function label(parent, text, size, x, y, color, width)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    font:SetPoint("TOPLEFT", x, y)
    font:SetFont(STANDARD_TEXT_FONT, size)
    font:SetTextColor(unpackColor(color or pale))
    labels[#labels+1]={font,color or pale}
    font:SetText(text)
    if width then
        font:SetWidth(width)
        font:SetJustifyH("LEFT")
        font:SetWordWrap(true)
    end
    return font
end

local function decorate(frame, fill, edge)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    frame:SetBackdropColor(fill[1],fill[2],fill[3],1)
    frame:SetBackdropBorderColor(unpackColor(edge))
end

local function button(parent, text, width, x, y, handler, accent)
    local control = CreateFrame("Button", nil, parent, "BackdropTemplate")
    control:SetSize(width, 31)
    control:SetPoint("TOPLEFT", x, y)
    local caption=control:CreateFontString(nil,"OVERLAY","GameFontNormal")
    caption:SetFont(STANDARD_TEXT_FONT,13)
    caption:SetTextColor(unpackColor(pale))
    caption:SetPoint("CENTER")
    control:SetFontString(caption)
    control:SetText(text)
    decorate(control,accent and palette.cta or palette.tag,accent and gold or palette.outline)
    control:SetScript("OnEnable",function()
        caption:SetTextColor(unpackColor(pale))
        decorate(control,accent and palette.cta or palette.tag,accent and gold or palette.outline)
    end)
    control:SetScript("OnDisable",function()
        caption:SetTextColor(unpackColor(muted))
        decorate(control,palette.panel,palette.outline)
    end)
    control:SetScript("OnClick", handler)
    control:SetScript("OnEnter",function()
        if control:IsEnabled() then control:SetBackdropBorderColor(unpackColor(gold)) end
    end)
    control:SetScript("OnLeave",function()
        control:SetBackdropBorderColor(unpackColor(accent and control:IsEnabled() and gold or palette.outline))
    end)
    return control
end

local function panel(y,height,fill,edge,parent,x,width)
    local control=CreateFrame("Frame",nil,parent or window,"BackdropTemplate")
    control:SetPoint("TOPLEFT",x or 24,y)
    control:SetSize(width or 417,height)
    decorate(control,fill or palette.panel,edge or palette.outline)
    return control
end

local function applyPreferences()
    local p=draftPreferences or context.preferences
    window:SetScale(p.scale or 1)
    for _,f in ipairs(labels) do
        local c=p.highContrast and (f[2]==gold and {1,.86,.55} or {1,1,1}) or f[2]
        f[1]:SetTextColor(unpackColor(c))
    end
end

local function openPreferences()
    if preferencesMode then return end
    local p=context.preferences
    draftPreferences={scale=p.scale or 1,highContrast=p.highContrast,reduceMotion=p.reduceMotion,sounds=p.sounds}
    preferencesMode=true
    UI.Refresh()
end

local function closePreferences(save)
    if save then
        for _,k in ipairs({"scale","highContrast","reduceMotion","sounds"}) do context.preferences[k]=draftPreferences[k] end
    end
    draftPreferences,preferencesMode=nil,nil
    UI.Refresh()
end

local function paintPhases(index)
    for i,p in ipairs(phases) do
        local c=i==index and gold or palette.outline
        decorate(p.frame,i==index and palette.selected or palette.panel,c)
        p.caption:SetTextColor(unpackColor(i==index and pale or i<index and palette.success or muted))
        p.caption:SetText(i==index and ("• "..p.text) or p.text)
    end
end

local function refreshPreparationClock()
    if not prepDeadline then return end
    local remaining = math.min(prepLimit or context.preparationSeconds, math.max(0, prepDeadline - context.serverNow()))
    local prefs=context.preferences
    endOfTimer:SetAlpha(not prefs.highContrast and not prefs.reduceMotion and remaining>0 and remaining<=5 and remaining%2==1 and .86 or 1)
    if remaining == prepSeconds then return end
    prepSeconds = remaining
    if prepHost then primary:SetEnabled(remaining == 0 and not prepBlocked) end
    if remaining > 0 then
        endOfTimer:SetText(("%d:%02d"):format(math.floor(remaining/60),remaining%60))
        status:SetText(("Time to prepare: %d:%02d"):format(math.floor(remaining / 60),remaining % 60))
    else
        endOfTimer:SetText("0:00")
        status:SetText(prepBlocked and "A contestant is unavailable. Wait for them to return."
            or prepHost and "Preparation complete. Begin the runway."
            or "Preparation complete. Waiting for the raid leader.")
    end
end

local function build()
    window = CreateFrame("Frame", "SYBAdminWindow", UIParent, "BackdropTemplate")
    window:SetSize(465, 537)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    decorate(window,palette.window,gold)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetScript("OnHide",function(self)
        self:StopMovingOrSizing()
        if preferencesMode then draftPreferences,preferencesMode=nil,nil;applyPreferences() end
    end)
    window:SetScript("OnUpdate", function(_, elapsed)
        if not (prepDeadline and prepSeconds~=0) and not voteDeadline then return end
        prepTick=prepTick+elapsed
        if prepTick<0.25 then return end
        prepTick=0
        if voteDeadline then
            local remaining=math.max(0,voteDeadline-context.serverNow())
            if remaining==0 then UI.Refresh()
            else
                endOfTimer:SetText(("%d:%02d"):format(math.floor(remaining/60),remaining%60))
                status:SetText(("Voting closes in %d:%02d"):format(math.floor(remaining/60),remaining%60))
            end
        else refreshPreparationClock() end
    end)

    windowHeader=panel(-17,53,palette.header,palette.trim)
    local logo=windowHeader:CreateTexture(nil,"ARTWORK")
    logo:SetSize(34,34)
    logo:SetPoint("LEFT",12,0)
    logo:SetTexture(assetPath.."BootsyMinimap.tga")
    brand=label(windowHeader,"STRUT YOUR BOOTSY",16,54,-9,gold)
    badge=label(windowHeader,"",10,54,-31,muted)
    for i,phase in ipairs({"Setup / Lobby","Preparation","Runway","Voting","Results"}) do
        local cell=panel(-78,28,palette.panel,palette.outline,window,24+(i-1)*84,81)
        local tag=label(cell,phase,10,0,0,muted,81)
        tag:ClearAllPoints()
        tag:SetPoint("CENTER")
        tag:SetJustifyH("CENTER")
        phases[i]={frame=cell,caption=tag,text=phase}
    end
    title=label(window,"Welcome to the runway",23,24,-115,pale,417)
    overview=panel(-151,102,palette.panel,palette.outline)
    summary=label(overview,"",14,13,-11,pale,391)
    endOfTimer=label(overview,"",25,13,-61,gold,391)
    heroName=label(overview,"",24,13,-30,pale,391)
    heroNext=label(overview,"",13,13,-71,gold,391)
    contestant = button(overview, "Contestant", 132, 18, -64, function()
        selectedRole = "contestant"
        UI.Refresh()
    end)
    spectator = button(overview, "Spectator", 132, 158, -64, function()
        selectedRole = "spectator"
        UI.Refresh()
    end)

    info = panel(-265, 150)
    details = label(info, "", 14, 18, -14, muted, 370)
    roleHint = label(info, "", 14, 18, -47, muted, 370)
    list = CreateFrame("ScrollFrame", "SYBRegistrationRosterScroll", info, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", 17, -42)
    list:SetSize(351, 98)
    listContent = CreateFrame("Frame", nil, list)
    listContent:SetSize(378, 98)
    list:SetScrollChild(listContent)

    actionNotice=label(window,"",12,25,-421,muted,415)
    status=label(window,"",13,25,-451,gold,415)
    local trim=window:CreateTexture(nil,"ARTWORK")
    trim:SetColorTexture(gold[1],gold[2],gold[3],.6)
    trim:SetSize(417,1)
    trim:SetPoint("TOPLEFT",24,-481)
    local jewel=window:CreateTexture(nil,"OVERLAY")
    jewel:SetTexture(assetPath.."ArmoryTrim.tga")
    jewel:SetSize(20,7)
    jewel:SetPoint("TOP",0,-478)
    primary = button(window, "Open registration", 152, 285, -485, function()
        local p = context.getProjection()
        if preferencesMode then closePreferences(true); return end
        if p.wizard then context.practiceAction("CONTINUE"); return end
        if p.practice then
            if p.phase=="runway_complete" then context.practiceAction("VOTING");return end
            if p.phase=="paused" then context.practiceAction("RESUME");return end
            if p.phase=="voting" then context.practiceAction(voteExpiry and "CLOSE_VOTE" or "SUBMIT");return end
            if p.phase=="round_results" then
                if p.reveal then
                    if p.revealCount>=math.min(#p.reveal,3) then context.restartPractice() else context.practiceAction("REVEAL") end
                else context.practiceAction(p.round<p.rounds and "NEXT_ROUND" or "AWARDS") end
                return
            end
        end
        if p.isLeader then
            if p.sessionId and p.phase == "registration" then context.start()
            elseif p.phase == "preparation" then context.beginRunway()
            elseif p.phase == "runway" then context.advanceRunway()
            elseif p.phase == "runway_complete" and p.practice then context.restartPractice()
            else context.openRegistration() end
        else
            context.submitRole(p.submittedRole or selectedRole)
        end
    end,true)
    secondary = button(window, "Refresh", 101, 28, -485, function()
        local p=context.getProjection()
        if preferencesMode then closePreferences(false);return end
        if p.wizard then context.practiceAction("BACK");return end
        if p.practice then context.leavePractice()
        elseif p.isLeader and p.sessionId and p.phase == "registration" then context.cancel()
        else context.refresh() end
    end)
    confirmPassive = button(window, "Confirm no addon", 140, 135, -485, function()
        if selectedObserver then context.confirmPassive(selectedObserver.name, selectedObserver.guid) end
    end)
    confirmPassive:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Confirm only after checking with this player that the addon is absent.")
        GameTooltip:Show()
    end)
    confirmPassive:SetScript("OnLeave", GameTooltip_Hide)

    skipPrep = button(window, "Skip countdown", 140, 135, -485, function() context.skipPreparation() end)
    utility=button(window,"",140,135,-485,function()
        local p=context.getProjection()
        if preferencesMode then
            draftPreferences={scale=1,highContrast=false,reduceMotion=false,sounds=false}
            UI.Refresh()
        elseif p.phase=="registration" and p.practice then context.practiceAction("SETUP")
        elseif p.phase=="runway" and p.practice then context.practiceAction("PAUSE")
        elseif p.phase=="voting" and p.practice then context.skipVote()
        else context.enterPractice() end
    end)
    prefsLink=button(windowHeader,"Options",58,310,-12,openPreferences)
    local close=button(windowHeader,"",25,380,-12,function() window:Hide() end)
    close:SetHeight(25)
    local closeIcon=close:CreateTexture(nil,"ARTWORK")
    closeIcon:SetTexture(assetPath.."ArmoryClose.tga")
    closeIcon:SetSize(13,13)
    closeIcon:SetPoint("CENTER")
    close:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("Close")
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave",GameTooltip_Hide)
    votePanel=panel(-265,150,palette.panel,palette.outline)
    for i=1,5 do
        local row=panel(-5-(i-1)*28,27,palette.window,palette.outline,votePanel,5,407)
        local item={frame=row,label=label(row,"",13,9,-6,pale,209),stars={}}
        for n=1,5 do
            local choice=n
            local control=button(row,"",26,233+(choice-1)*30,-2,function()
                context.practiceAction("RATE",item.name,choice)
            end)
            control:SetHeight(23)
            control.rating=choice
            local star=control:CreateTexture(nil,"ARTWORK")
            star:SetSize(16,16)
            star:SetPoint("CENTER")
            control.starTexture=star
            control:SetScript("OnEnter",function(self)
                GameTooltip:SetOwner(self,"ANCHOR_TOP")
                GameTooltip:SetText("Rate "..item.name.." "..choice.." of 5")
                GameTooltip:Show()
            end)
            control:SetScript("OnLeave",GameTooltip_Hide)
            item.stars[choice]=control
        end
        ratingRows[i]=item
    end
    window:Hide()
    table.insert(UISpecialFrames, "SYBAdminWindow")
end

local function updateRoster(members, runway)
    local pitch, height = runway and 27 or 26, runway and 135 or 105
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", 17, runway and -9 or -37)
    list:SetSize(378, height)
    local stillSelected
    for index, member in ipairs(members) do
        local row = rows[index]
        if not row then
            row = button(listContent, "", 374, 0, -(index - 1) * 26, function(self)
                selectedObserver = self.member
                UI.Refresh()
            end)
            rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * pitch)
        row:SetHeight(pitch - 1)
        row.member = member
        local selected = selectedObserver and selectedObserver.guid == member.guid
        if selected and member.presence == "unknown" then stillSelected = member end
        local role = member.role and (" / " .. member.role) or ""
        if runway then
            row:SetText(member.name .. "  ·  " .. member.label)
            decorate(row,member.label=="Presenting" and palette.selected or palette.panel,
                member.label=="Presenting" and gold or palette.outline)
            -- Text is read-only, but stays legible instead of using the disabled skin.
            row:SetEnabled(true)
            row:EnableMouse(false)
        else
            decorate(row,selected and palette.selected or palette.panel,selected and gold or palette.outline)
            row:SetText((selected and "> " or "") .. member.name .. "  " .. presenceLabels[member.presence] .. role)
            row:EnableMouse(true)
            row:SetEnabled(member.presence == "unknown")
        end
        row:Show()
    end
    for i = #members + 1, #rows do rows[i]:Hide() end
    listContent:SetHeight(math.max(height, #members * pitch))
    selectedObserver = stillSelected
end

local function actionLabel(control,text,enabled)
    control:SetText(text)
    control:SetShown(true)
    control:SetEnabled(enabled~=false)
end

local function optionRows(items)
    list:Hide()
    for i,item in ipairs(items) do
        local control=choices[i]
        if not control then
            control=button(info,"",385,16,-(7+(i-1)*28),function(self)
                if self.action then self.action() end
            end)
            control:SetHeight(26)
            choices[i]=control
        end
        control.action=item[2]
        control:SetText(item[1])
        control:SetEnabled(true)
        control:EnableMouse(item[2]~=nil)
        decorate(control,item[3] and palette.selected or palette.panel,item[3] and gold or palette.outline)
        control:Show()
    end
end

local function showSettings(p)
    local cfg,w=p.settings,p.wizard
    local data={
        {"How many rounds?", "Choose 1–5 rounds.", "rounds", {1,2,3,4,5}},
        {"Choose themes","Choose a theme, or draw from the local practice pool.","theme",themeNames},
        {"Preparation timer","How much time do contestants have to get ready?","prep",{60,120,180}},
        {"Voting timer","Voting remains open until the timer expires.","vote",{30,60,90}},
    }
    local step=data[w]
    title:SetText(step and step[1] or "Review your contest")
    summary:SetText("Setup · "..w.." of 5\n"..(step and step[2] or "Check the settings before returning to registration."))
    details:SetText("")
    roleHint:SetText("")
    local opts={}
    if step then
        for _,x in ipairs(step[4]) do
            local k,val=step[3],x
            local display=type(val)=="number" and (k=="rounds" and tostring(val) or (("%d:%02d"):format(math.floor(val/60),val%60))) or val
            local selected=cfg[k]==val
            opts[#opts+1]={(selected and "Selected: " or "")..display,
                function() context.practiceAction("SETTING",k,val) end, selected}
        end
    else
        opts={{"Rounds: "..cfg.rounds},{"Theme: "..cfg.theme},{"Preparation: "..cfg.prep.." seconds"},{"Voting: "..cfg.vote.." seconds"}}
    end
    optionRows(opts)
    actionLabel(secondary,w==1 and "Cancel" or "Back")
    actionLabel(primary,w==5 and "Return to lobby" or "Continue")
    return "Practice setup only. Raid settings are unchanged."
end

local function showPreferences()
    title:SetText("Interface preferences")
    summary:SetText("Preferences are saved for this character.\nPreview changes before saving.")
    details:SetText("")
    roleHint:SetText("")
    local p=draftPreferences
    local values={.75,1,1.25,1.5}
    local titleText={highContrast="High contrast",reduceMotion="Reduce motion",sounds="Optional sounds"}
    local choices={
        {("Window scale: %d%%"):format(p.scale*100),function()
            local i=1
            for n,x in ipairs(values) do if x==p.scale then i=n end end
            p.scale=values[i%#values+1]
            UI.Refresh()
        end,true}
    }
    for _,name in ipairs({"highContrast","reduceMotion","sounds"}) do
        local key=name
        choices[#choices+1]={titleText[key]..": "..(p[key] and "On" or "Off"),
            function() p[key]=not p[key];UI.Refresh() end,p[key]}
    end
    optionRows(choices)
    actionLabel(primary,"Save preferences")
    actionLabel(secondary,"Cancel")
    actionLabel(utility,"Reset")
    return "Click the scale or an option to change it."
end

local function showBallot(p)
    local remaining=math.max(0,p.voteEndsAt-context.serverNow())
    local closed=remaining==0
    voteExpiry=closed
    voteDeadline=not closed and p.voteEndsAt or nil
    voteSubmitted=p.ballotSubmitted
    title:SetText(closed and "Voting has closed" or voteSubmitted and "Ballot submitted" or "Judge contestants")
    summary:SetText("Round "..p.round.." of "..p.rounds.." · Practice voting\nSample ballot as "..p.practiceVoter..".")
    endOfTimer:SetText(("%d:%02d"):format(math.floor(remaining/60),remaining%60))
    info:Hide()
    votePanel:Show()
    local edits=false
    for i,row in ipairs(ratingRows) do
        row.name=p.runwayOrder[i]
        row.label:SetText(row.name==p.practiceVoter and (row.name.." · You (no self-rating)") or row.name)
        for n,control in ipairs(row.stars) do
            local rating=p.ballot[row.name] or 0
            edits=edits or rating>0
            control.ratedName=row.name
            control.starTexture:SetTexture(assetPath..(n<=rating and "ArmoryStarOn.tga" or "ArmoryStarOff.tga"))
            control:SetShown(row.name~=p.practiceVoter)
            control:SetEnabled(not (closed or voteSubmitted))
            decorate(control,n<=rating and palette.selected or palette.panel,n<=rating and gold or palette.outline)
        end
    end
    actionLabel(primary,closed and "View round results" or "Submit ballot",closed or edits and not voteSubmitted)
    actionLabel(utility,"Skip vote timer",not closed)
    if closed then return "Voting is closed. Only submitted ratings will count." end
    if voteSubmitted then return "Ballot locked. Voting stays open until the timer ends." end
    return "Partial ballots are allowed. Select 1–5 stars; click again to clear."
end

local function showResults(p)
    local last=p.round==p.rounds
    details:SetText("")
    roleHint:SetText("")
    if not p.reveal then
        title:SetText("Round results")
        summary:SetText(("Round %d of %d complete\nPractice aggregate scores"):format(p.round,p.rounds))
        local items={}
        for _,r in ipairs(p.result) do items[#items+1]={r.name.." · "..(r.average and ("%.1f / 5"):format(r.average) or "Not rated")} end
        optionRows(items)
        actionLabel(primary,last and "Final awards" or ("Begin round "..(p.round+1)))
        return "Only aggregate scores are shown. No player was contacted."
    end
    title:SetText("Final awards")
    summary:SetText("Practice podium\nQualified in every round: "..#p.reveal)
    local places={"1st place","2nd place","3rd place"}
    local max=math.min(3,#p.reveal)
    local opts={}
    for i=1,max do
        local reveal=i>max-p.revealCount
        opts[#opts+1]={places[i].." · "..(reveal and p.reveal[i].name or "Not revealed"),nil,reveal}
    end
    if p.reveal[4] and p.revealCount==max then opts[#opts+1]={"Honorable mention · "..p.reveal[4].name} end
    if max==0 then opts[1]={"No contestants received a rating in every round."} end
    optionRows(opts)
    actionLabel(primary,p.revealCount>=max and "Practice again" or "Next reveal")
    return p.revealCount>=max and "The practice contest is complete." or "The podium is revealed in reverse order."
end

function UI.Refresh()
    if not window or not window:IsShown() then return end
    local p = context.getProjection()
    if sessionId ~= p.sessionId then
        sessionId, selectedRole, selectedObserver = p.sessionId, nil, nil
        list:SetVerticalScroll(0)
    end
    local registration = p.sessionId and p.phase == "registration"
    local lobby = registration and p.isLeader
    local chooser = registration and not p.isLeader and p.lobbyState ~= "late_joiner" and p.lobbyState ~= "disconnected"
    local prompt
    prepDeadline, prepSeconds, prepTick, prepHost, prepBlocked = nil, nil, 0, false, false
    voteDeadline,voteExpiry,voteSubmitted=nil,nil,nil
    for _,choice in ipairs(choices) do choice:Hide() end
    info:Show()
    votePanel:Hide()
    utility:Hide()
    endOfTimer:SetText("")
    endOfTimer:SetAlpha(1)
    heroName:SetText("")
    heroNext:SetText("")
    applyPreferences()
    local phaseIndex=({preparation=2,runway=3,paused=3,runway_complete=3,voting=4,round_results=5})[p.phase]
    paintPhases(preferencesMode and 0 or phaseIndex or 1)
    decorate(overview,p.phase=="runway" and palette.selected or palette.panel,
        p.phase=="runway" and palette.trim or palette.outline)
    badge:SetText(p.practice and "PRACTICE MODE  /  FICTIONAL ROSTER" or p.isLeader and "RAID LEADER CONSOLE"
        or p.localRole and p.localRole:upper() or "RAID FASHION CONTEST")
    brand:SetText("STRUT YOUR BOOTSY")
    primary:SetShown(true)
    list:SetShown(lobby == true or (p.phase == "runway" and p.runwayOrder ~= nil))
    contestant:SetShown(chooser == true)
    spectator:SetShown(chooser == true)
    confirmPassive:SetShown(lobby == true and not p.practice)
    skipPrep:SetShown(p.practice == true and p.phase == "preparation")
    secondary:SetText(p.practice and "Exit practice" or lobby and "Cancel" or "Refresh")

    if preferencesMode then
        contestant:Hide();spectator:Hide();confirmPassive:Hide();skipPrep:Hide()
        prompt=showPreferences()
    elseif p.wizard then
        prompt=showSettings(p)
    elseif p.practice and p.phase=="voting" then
        prompt=showBallot(p)
    elseif p.practice and p.phase=="round_results" then
        prompt=showResults(p)
    elseif p.practice and p.phase=="paused" then
        title:SetText("Runway paused")
        summary:SetText("The same contestant will resume when you’re ready.")
        details:SetText("Practice recovery")
        roleHint:SetText("The runway has not advanced.")
        actionLabel(primary,"Resume runway")
        prompt="Only the practice contest is paused."
    elseif lobby then
        title:SetText("Registration lobby")
        if p.practice then actionLabel(utility,"Setup") end
        summary:SetText(("Contestants: %d / 5 minimum\nSpectators: %d\nPending addon responses: %d"):format(
            p.contestants, p.spectators, p.pendingResponses))
        details:SetText("Raid roster")
        roleHint:SetText("")
        updateRoster(p.members)
        confirmPassive:SetEnabled(selectedObserver ~= nil and p.discoveryComplete == true)
        primary:SetText("Start contest")
        primary:SetEnabled(p.lobbyState == "ready_to_start")
        prompt = p.lobbyState == "ready_to_start"
            and (p.practice and "Five fictional contestants. No raid messages are sent."
                or "Ready to start. The administrator does not compete or vote.")
            or (messages[p.lobbyState] or "Start is unavailable. Refresh the raid roster and check /syb status.")
    elseif chooser then
        local role = p.localRole or p.submittedRole or selectedRole
        title:SetText("Choose your role")
        summary:SetText("Your participation")
        contestant:SetText(role == "contestant" and "Selected: Contestant" or "Contestant")
        spectator:SetText(role == "spectator" and "Selected: Spectator" or "Spectator")
        local canChoose = not p.localRole and not p.awaiting and not p.timedOut
        contestant:SetEnabled(canChoose)
        spectator:SetEnabled(canChoose)
        details:SetText(role == "spectator" and "Spectator rules" or "Contestant rules")
        roleHint:SetText(role == "spectator" and "Watch the runway and vote each round." or
            "Present your outfit each round. Vote for others.")
        primary:SetText(p.timedOut and "Retry confirmation" or "Confirm role")
        primary:SetEnabled(role ~= nil and not p.localRole and not p.awaiting)
        if p.localRole then prompt = "Registered as " .. p.localRole .. ". Awaiting the administrator."
        elseif p.awaiting then prompt = "Role submitted. Waiting for the raid leader."
        elseif p.timedOut then prompt = "Confirmation timed out. Retry the same request."
        else prompt = "Select a role and confirm it." end
    elseif p.phase == "preparation" then
        title:SetText(("Round %d of %d: Preparation"):format(p.round or 1,p.rounds or 1))
        local role = "Observer"
        if p.isLeader then role = "Administrator"
        elseif p.lobbyState ~= "late_joiner" then
            if p.localRole == "contestant" then role = "Contestant"
            elseif p.localRole == "spectator" then role = "Spectator" end
        end
        summary:SetText("Registration is closed.\nYour role: " .. role)
        details:SetText(p.preparation and ("Theme: " .. p.preparation.theme) or "Waiting for the theme…")
        roleHint:SetText(role == "Contestant" and "Get your outfit ready."
            or role == "Administrator" and "Give contestants time to get their outfits ready."
            or "Contestants are getting their outfits ready.")
        prepHost, prepBlocked = p.isLeader == true, p.runwayBlocked == true
        prepLimit=p.settings and p.settings.prep or nil
        primary:SetText("Begin runway")
        primary:SetShown(prepHost)
        primary:SetEnabled(false)
        prepDeadline = p.preparation and p.preparation.endsAt
        prompt = prepDeadline and "" or "Syncing the countdown with the raid leader…"
    elseif p.phase == "runway" and p.runway then
        local r = p.runway
        title:SetText(("Round %d of %d: Runway"):format(p.round or 1,p.rounds or 1))
        if p.practice then actionLabel(utility,"Pause") end
        summary:SetText(("Presenting  %d of %d"):format(r.index,r.total))
        heroName:SetText(r.current)
        heroNext:SetText(r.upcoming and "Up next: " .. r.upcoming or "Final presentation")
        if p.runwayOrder then
            details:SetText("Runway order")
            roleHint:SetText("")
            local order = {}
            for i,name in ipairs(p.runwayOrder) do
                order[i] = {name=name,label=i<r.index and "Presented" or i==r.index and "Presenting"
                    or i==r.index+1 and "Up next" or "Waiting"}
            end
            updateRoster(order,true)
        else
            details:SetText("Runway status")
            roleHint:SetText("The raid leader advances the runway.")
        end
        primary:SetText(r.index==r.total and "Finish runway" or "Next contestant")
        primary:SetShown(p.isLeader == true)
        primary:SetEnabled(p.isLeader == true and not p.runwayBlocked)
        prompt = p.runwayBlocked and "A contestant is unavailable. Wait for them to return." or ""
    elseif p.phase == "runway_complete" and p.runway then
        title:SetText("Runway complete")
        summary:SetText(("%d of %d contestants presented."):format(p.runway.total,p.runway.total))
        details:SetText(p.practice and "Voting is next" or "End of this live test build")
        roleHint:SetText(p.practice and "Try an anonymous sample ballot with the fictional roster."
            or "Live voting is not included yet. Use solo practice to try a ballot.")
        primary:SetText("Begin voting")
        primary:SetShown(p.practice == true)
        primary:SetEnabled(p.practice == true)
        prompt = ""
    else
        title:SetText("Welcome to the runway")
        summary:SetText((IsInRaid() and "In raid" or "Not in a raid. Join a raid to participate.") ..
            "\nRaid leader: " .. (p.leader or "none"))
        details:SetText("Contest status")
        roleHint:SetText(p.phase == "ended" and "The raid registration session ended." or
            registration and "Raid registration is open." or "No active contest.")
        primary:SetText("Open registration")
        primary:SetEnabled(p.isLeader == true and (not p.sessionId or p.phase == "ended"))
        if context.groupActive and not context.groupActive() then actionLabel(utility,"Practice mode") end
        prompt = (registration or p.lobbyState == "late_joiner") and messages[p.lobbyState] or ""
    end
    local noticeText = p.notice and (messages[p.notice] or ("Action failed (" .. p.notice .. "). Refresh and try again."))
    actionNotice:SetText(noticeText and noticeText ~= prompt and noticeText or "")
    status:SetText(prompt)
    refreshPreparationClock()
end

function UI.Show()
    if not window then build() end
    window:Show()
    UI.Refresh()
end

function UI.Toggle()
    if window and window:IsShown() then window:Hide() else UI.Show() end
end

local function positionLauncher(angle)
    launcher:ClearAllPoints()
    launcher:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * (Minimap:GetWidth() / 2 + 7),
        math.sin(angle) * (Minimap:GetHeight() / 2 + 7))
end

function UI.Initialize(options)
    context = options
    context.preferences=context.preferences or {}
    if launcher or not Minimap then return end
    launcher = CreateFrame("Button", "SYBMinimapLauncher", Minimap)
    launcher:SetSize(26, 26)
    positionLauncher(context.preferences.launcherAngle or -2.25)
    launcher:SetNormalTexture("Interface\\AddOns\\StrutYourBootsy\\Assets\\BootsyMinimap.tga")
    launcher:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    launcher:RegisterForDrag("LeftButton")
    launcher:SetScript("OnClick", UI.Toggle)
    launcher:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.atan2(y / scale - centerY, x / scale - centerX)
            context.preferences.launcherAngle = angle
            positionLauncher(angle)
        end)
    end)
    launcher:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    launcher:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Strut Your Bootsy")
        GameTooltip:AddLine("Click to toggle the window. Drag to move the launcher.", 1, 1, 1)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", GameTooltip_Hide)
end
