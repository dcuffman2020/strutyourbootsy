local addonName, ns = ...
local UI = {}
ns.UI = UI

local window, launcher
local brand, title, summary, details, status, actionNotice, roleHint, list, listContent
local primary, secondary, contestant, spectator, confirmPassive, skipPrep, utility, prefsLink
local badge, windowHeader, overview, info, votePanel, endOfTimer, heroName, heroNext
local phases, choices, ratingRows = {}, {}, {}
local preferencesMode, draftPreferences
local extra={}
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
-- Approved Armory gold, cool neutral and warm trim, reused as medal surfaces.
local medals={
    {fill=gold,edge=rgb(0x866638),ink=palette.window},
    {fill=muted,edge=palette.outline,ink=palette.window},
    {fill=palette.trim,edge=gold,ink={1,1,1}},
}
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
    invalid_theme="Enter a valid theme name.",
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
    caption:SetWidth(width-12)
    caption:SetJustifyH("CENTER")
    caption:SetWordWrap(false)
    caption:SetMaxLines(1)
    control.caption=caption
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
        control:SetBackdropBorderColor(unpackColor((control.selected or accent and control:IsEnabled()) and gold or palette.outline))
    end)
    return control
end

local function paintSelection(control,selected)
    control.selected=selected==true
    decorate(control,selected and palette.selected or palette.panel,selected and gold or palette.outline)
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

local function closeTheme()
    extra.themeEditor,extra.themeFeedback=nil,nil
    extra.themeInput:ClearFocus()
    UI.Refresh()
end

local function useTheme(random)
    if not extra.themeEditor or extra.previewName then return end
    local label
    if not random then
        label=context.normalizeTheme(extra.themeInput:GetText())
        if not label then return end
    end
    local ok,reason=context.setCustomTheme(label)
    if ok then closeTheme()
    else extra.themeFeedback=messages[reason] or "Could not save this theme.";UI.Refresh() end
end

local function openTheme()
    local p=context.getProjection()
    if extra.previewName or p.phase~="registration" or not p.isLeader then return end
    extra.themeEditor,extra.themeFeedback=true,nil
    extra.themeInput:SetText(p.customTheme or "")
    UI.Refresh()
    extra.themeInput:SetFocus()
    extra.themeInput:HighlightText()
end

local function paintPhases(index)
    for i,p in ipairs(phases) do
        local c=i==index and gold or palette.outline
        decorate(p.frame,i==index and palette.selected or palette.panel,c)
        p.caption:SetTextColor(unpackColor(i==index and pale or i<index and palette.success or muted))
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

local function buildThemeAndPreviewControls()
    extra.viewButton=button(windowHeader,"View as",78,238,-12,function()
        if extra.previewName then extra.previewName,extra.viewPicker=nil,nil
        else extra.viewPicker=not extra.viewPicker end
        UI.Refresh()
    end)
    extra.themeButton=button(overview,"Theme...",113,291,-66,openTheme)
    extra.timerButton=button(overview,"Runway timer",114,168,-66,function()
        extra.timerSetup=true
        UI.Refresh()
    end)
    extra.turnClock=label(overview,"",15,260,-12,gold,142)
    extra.turnClock:SetJustifyH("RIGHT")
    extra.themeInput=CreateFrame("EditBox","SYBThemeInput",info,"InputBoxTemplate")
    extra.themeInput:SetSize(370,30)
    extra.themeInput:SetPoint("TOPLEFT",19,-20)
    extra.themeInput:SetAutoFocus(false)
    extra.themeInput:SetMaxLetters(48)
    extra.themeInput:SetScript("OnEscapePressed",closeTheme)
    extra.themeInput:SetScript("OnEnterPressed",function() useTheme(false) end)
    extra.themeInput:SetScript("OnTextChanged",function() if extra.themeEditor then extra.themeFeedback=nil;UI.Refresh() end end)
end

local function presenting(p)
    if p.isLeader or p.localRole~="contestant" or p.phase~="runway" or not p.runway or p.runwayBlocked then return false end
    local actor=p.practice and extra.previewName or not p.practice and context.playerName()
    return actor and actor==p.runway.current
end

local runwayFavorites={"Bow","Wave","Dance","Flex","Chicken"}
local runwayEmotes={"Cheer","Clap","Cry","Gasp","Grin","Kneel","Laugh","Nod","Point","Purr","Roar",
    "Salute","Shiver","Shrug","Sigh","Sit","Smile","Thank","Wink","Yawn"}

local function loadRunwayEmotes()
    local pool={}
    for i,name in ipairs(runwayEmotes) do pool[i]=name end
    for i=1,15 do
        local j=math.random(i,#pool)
        pool[i],pool[j]=pool[j],pool[i]
        extra.emoteButtons[#runwayFavorites+i]:SetText(pool[i])
    end
    extra.emotesLoaded=true
end

local function buildEmoteDrawer()
    local function canChoose()
        return window:IsShown() and extra.emoteToggle:IsShown() and presenting(context.getProjection())
    end
    -- Practice uses an explicit preview role on an otherwise read-only host projection.
    local function canPreview()
        local p=context.getProjection()
        return window:IsShown() and extra.emoteToggle:IsShown() and p.practice and extra.previewName
            and p.phase=="runway" and p.runway and p.runway.current==extra.previewName and not p.runwayBlocked
    end
    extra.emoteToggle=button(info,"Emotes +",135,264,-8,function()
        if not (canChoose() or canPreview()) then return end
        extra.emoteOpen=not extra.emoteOpen
        if extra.emoteOpen and not extra.emotesLoaded then loadRunwayEmotes() end
        if not extra.emoteOpen then extra.emoteFeedback=nil end
        UI.Refresh()
    end)
    extra.emoteDrawer=panel(-68,125,palette.window,palette.trim,info,17,383)
    extra.emoteNote=label(extra.emoteDrawer,"",11,8,-107,muted,367)
    extra.emoteButtons={}
    for i=1,20 do
        local row,column=math.floor((i-1)/5),(i-1)%5
        local width,start=66,14
        local control=button(extra.emoteDrawer,runwayFavorites[i] or "",width,start+column*(width+6),-6-row*25,function(self)
            if not extra.emoteDrawer:IsShown() or not extra.emoteOpen then return end
            local name=self:GetText()
            if not name or name=="" then return end
            if canPreview() then
                extra.emoteFeedback="Practice: "..name.." selected. Nothing was sent to WoW."
            elseif canChoose() then
                local api=C_ChatInfo and C_ChatInfo.PerformEmote
                local ok,performed
                if type(api)=="function" then ok,performed=pcall(api,name:upper()) end
                extra.emoteFeedback=ok and performed==true and ("Performed "..name..".")
                    or "Emote unavailable. Try your usual chat command."
            else return end
            UI.Refresh()
        end)
        control:SetHeight(22)
        control.caption:SetFont(STANDARD_TEXT_FONT,12)
        extra.emoteButtons[i]=control
    end
end

local function updateEmoteDrawer(p)
    local active=presenting(p) and not preferencesMode and not extra.viewPicker
    local key=active and table.concat({p.sessionId or "",p.round or 1,p.runway.index,p.runway.current},":") or nil
    if key~=extra.emoteTurn then
        extra.emoteTurn,extra.emoteOpen,extra.emoteFeedback,extra.emotesLoaded=key,nil,nil,nil
    end
    extra.emoteToggle:SetShown(key~=nil)
    extra.emoteToggle:SetText(extra.emoteOpen and "Emotes −" or "Emotes +")
    local expanded=key~=nil and extra.emoteOpen==true
    window:SetHeight(expanded and 589 or 564)
    if expanded then info:SetHeight(200) end
    extra.emoteDrawer:SetShown(expanded)
    extra.emoteNote:SetText(extra.emoteFeedback or (p.preview and "Practice only. Emotes won’t play in WoW." or "Choose an emote to perform it."))
end

local function build()
    window = CreateFrame("Frame", "SYBAdminWindow", UIParent, "BackdropTemplate")
    window:SetSize(465, 564)
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
        extra.themeEditor,extra.viewPicker,extra.timerSetup=nil,nil,nil
        extra.emoteOpen,extra.emoteFeedback=nil,nil
        if extra.themeInput then extra.themeInput:ClearFocus() end
    end)
    window:SetScript("OnUpdate", function(_, elapsed)
        if not (prepDeadline and prepSeconds~=0) and not voteDeadline and not extra.turnDeadline then return end
        prepTick=prepTick+elapsed
        if prepTick<0.25 then return end
        prepTick=0
        if extra.turnDeadline then
            UI.UpdateRunwayClock()
        elseif voteDeadline then
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
    badge=label(windowHeader,"",10,54,-31,muted,175)
    badge:SetMaxLines(1)
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
    contestant = button(overview, "Contestant", 148, 18, -64, function()
        selectedRole = "contestant"
        UI.Refresh()
    end)
    spectator = button(overview, "Spectator", 148, 174, -64, function()
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

    actionNotice=label(window,"",12,25,-445,muted,415)
    status=label(window,"",13,25,-474,gold,415)
    actionNotice:ClearAllPoints()
    actionNotice:SetPoint("TOPLEFT",window,"BOTTOMLEFT",25,119)
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT",window,"BOTTOMLEFT",25,90)
    local trim=window:CreateTexture(nil,"ARTWORK")
    trim:SetColorTexture(gold[1],gold[2],gold[3],.6)
    trim:SetSize(417,1)
    trim:SetPoint("TOPLEFT",window,"BOTTOMLEFT",24,60)
    local jewel=window:CreateTexture(nil,"OVERLAY")
    jewel:SetTexture(assetPath.."ArmoryTrim.tga")
    jewel:SetSize(20,7)
    jewel:SetPoint("TOP",window,"BOTTOM",0,63)
    primary = button(window, "Open registration", 152, 285, -516, function()
        local p = context.getProjection()
        if preferencesMode then closePreferences(true); return end
        if extra.themeEditor then useTheme(false);return end
        if extra.previewName or extra.viewPicker then return end
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
    secondary = button(window, "Refresh", 101, 28, -516, function()
        local p=context.getProjection()
        if preferencesMode then closePreferences(false);return end
        if extra.themeEditor then closeTheme();return end
        if extra.timerSetup then extra.timerSetup=nil;UI.Refresh();return end
        if extra.viewPicker or extra.previewName then extra.viewPicker,extra.previewName=nil,nil;UI.Refresh();return end
        if p.wizard then context.practiceAction("BACK");return end
        if p.practice then context.leavePractice()
        elseif p.isLeader and p.sessionId and p.phase == "registration" then context.cancel()
        else context.refresh() end
    end)
    confirmPassive = button(window, "Confirm no addon", 140, 135, -516, function()
        if selectedObserver then context.confirmPassive(selectedObserver.name, selectedObserver.guid) end
    end)
    confirmPassive:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Confirm only after checking with this player that the addon is absent.")
        GameTooltip:Show()
    end)
    confirmPassive:SetScript("OnLeave", GameTooltip_Hide)

    skipPrep = button(window, "Skip countdown", 140, 135, -516, function() context.skipPreparation() end)
    utility=button(window,"",140,135,-516,function()
        local p=context.getProjection()
        if extra.themeEditor then useTheme(true);return end
        if extra.previewName or extra.viewPicker then return end
        if preferencesMode then
            draftPreferences={scale=1,highContrast=false,reduceMotion=false,sounds=false}
            UI.Refresh()
        elseif p.phase=="registration" and p.practice then context.practiceAction("SETUP")
        elseif p.phase=="runway" and p.practice then context.practiceAction("PAUSE")
        elseif p.phase=="voting" and p.practice then context.skipVote()
        else context.enterPractice() end
    end)
    for _,entry in ipairs({{primary,285},{secondary,28},{confirmPassive,135},{skipPrep,135},{utility,135}}) do
        entry[1]:ClearAllPoints()
        entry[1]:SetPoint("TOPLEFT",window,"BOTTOMLEFT",entry[2],48)
    end
    prefsLink=button(windowHeader,"Options",58,318,-12,openPreferences)
    buildThemeAndPreviewControls()
    buildEmoteDrawer()
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
                if not extra.previewName then context.practiceAction("RATE",item.name,choice) end
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

local function optionRows(items,customFirst)
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
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT",16,customFirst and (i==1 and -7 or -(41+(i-2)*25)) or -(7+(i-1)*28))
        control:SetHeight(customFirst and (i==1 and 31 or 23) or 26)
        control.caption:SetMaxLines(customFirst and i==1 and 2 or 1)
        -- WoW requires an explicit boolean even when customFirst is omitted.
        control.caption:SetWordWrap(customFirst == true and i==1)
        control.action=item[2]
        control:SetText(item[1])
        control:SetEnabled(true)
        control:EnableMouse(item[2]~=nil)
        paintSelection(control,item[3])
        local medal=medals[item[4]]
        control.caption:SetTextColor(unpackColor(medal and medal.ink or pale))
        if medal then decorate(control,medal.fill,medal.edge) end
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
    local hint=w==1 and ("Your contest will have %d %s."):format(cfg.rounds,cfg.rounds==1 and "round" or "rounds")
        or step and step[2] or "Check the settings before returning to registration."
    summary:SetText("Setup · "..w.." of 5\n"..hint)
    details:SetText("")
    roleHint:SetText("")
    local opts={}
    local hasCustom=w==2 and cfg.customTheme~=nil
    if hasCustom then
        opts[1]={"Custom theme: "..cfg.customTheme,openTheme,true}
        info:SetHeight(172)
    end
    if step then
        for _,x in ipairs(step[4]) do
            local k,val=step[3],x
            local display=type(val)=="number" and (k=="rounds" and tostring(val) or (("%d:%02d"):format(math.floor(val/60),val%60))) or val
            local selected=cfg[k]==val and not (k=="theme" and cfg.customTheme)
            opts[#opts+1]={display,
                function() context.practiceAction("SETTING",k,val) end, selected}
        end
    else
        opts={{"Rounds: "..cfg.rounds},{"Theme: "..(cfg.customTheme or cfg.theme)},{"Preparation: "..cfg.prep.." seconds"},{"Voting: "..cfg.vote.." seconds"}}
    end
    optionRows(opts,hasCustom)
    actionLabel(secondary,w==1 and "Cancel" or "Back")
    actionLabel(primary,w==5 and "Return to lobby" or "Continue")
    if w==2 then
        actionLabel(extra.themeButton,hasCustom and "Edit theme" or "Custom theme")
        return hasCustom and "Click the highlighted custom theme to edit it." or "Choose a theme or enter a custom name."
    end
    return "Practice setup only. Raid settings are unchanged."
end

local function clockText(seconds)
    return ("%d:%02d"):format(math.floor(seconds/60),seconds%60)
end

function UI.UpdateRunwayClock()
    if not extra.turnDeadline then return end
    local left=math.max(0,extra.turnDeadline-context.serverNow())
    extra.turnClock:SetText(left>0 and ("Turn "..clockText(left)) or "Time’s up")
    if left==0 then extra.turnDeadline=nil end
end

local function showRunwayTimer(p)
    title:SetText("Runway timer")
    summary:SetText("Time per contestant\nStarts when the raid leader begins the runway or advances a turn.")
    details:SetText("")
    roleHint:SetText("")
    local options={}
    for _,x in ipairs(context.runwayOptions) do
        local seconds=x
        local selected=p.runwaySeconds==seconds
        options[#options+1]={clockText(seconds),
            function()
                local ok=context.setRunwaySeconds(seconds)
                if ok then extra.timerSetup=nil end
                UI.Refresh()
            end,selected}
    end
    optionRows(options)
    actionLabel(secondary,"Back")
    primary:Hide()
    return "Time running out does not advance the runway."
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
    summary:SetText("Round "..p.round.." of "..p.rounds.." · Practice voting\n"..
        (p.preview and ("Viewing "..p.practiceVoter.."’s ballot.") or ("Sample ballot as "..p.practiceVoter..".")))
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
            control:SetEnabled(not (closed or voteSubmitted or p.preview))
            decorate(control,n<=rating and palette.selected or palette.panel,n<=rating and gold or palette.outline)
        end
    end
    actionLabel(primary,closed and "View round results" or "Submit ballot",closed or edits and not voteSubmitted)
    actionLabel(utility,"Skip vote timer",not closed)
    if p.preview then
        primary:Hide();utility:Hide()
        return "Read-only preview. Return to host view to continue the walkthrough."
    end
    if closed then return "Voting is closed. Only submitted ratings will count." end
    if voteSubmitted then return "Ballot locked. Voting stays open until the timer ends." end
    return "Partial ballots are allowed. Select 1–5 stars; click again to clear."
end

local function showResults(p)
    local last=p.round==p.rounds
    details:SetText("")
    roleHint:SetText("")
    local places={"1st place","2nd place","3rd place"}
    if not p.reveal then
        title:SetText("Round results")
        summary:SetText(("Round %d of %d complete\nPractice aggregate scores"):format(p.round,p.rounds))
        local items={}
        local rank,previous=0,nil
        for i,r in ipairs(p.result) do
            local score=r.average
            if score~=previous then rank=i end
            local nextResult=p.result[i+1]
            local place=score and places[rank]
            local tied=score and (score==previous or (nextResult and nextResult.average==score))
            local caption=(place and ((tied and "Tied for " or "")..place.." · ") or "")..r.name
                .." · "..(score and ("%.1f / 5"):format(score) or "Not rated")
            items[#items+1]={caption,nil,nil,place and rank or nil}
            previous=score
        end
        optionRows(items)
        actionLabel(primary,last and "Final awards" or ("Begin round "..(p.round+1)))
        return "Only aggregate scores are shown. No player was contacted."
    end
    title:SetText("Final awards")
    summary:SetText("Practice podium\nQualified in every round: "..#p.reveal)
    local max=math.min(3,#p.reveal)
    local opts={}
    for i=1,max do
        local reveal=i>max-p.revealCount
        opts[#opts+1]={places[i].." · "..(reveal and p.reveal[i].name or "Not revealed"),nil,nil,reveal and i or nil}
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
    if p.phase~="registration" then extra.timerSetup=nil end
    if not p.practice or extra.previewSession and extra.previewSession~=p.sessionId then
        extra.previewName,extra.viewPicker,extra.previewSession=nil,nil,nil
    end
    if p.phase~="registration" and extra.themeEditor then extra.themeEditor=nil;extra.themeInput:ClearFocus() end
    if extra.previewName and p.practice then
        p.preview,p.isLeader,p.localRole=true,false,"contestant"
        p.practiceVoter,p.ballot,p.ballotSubmitted=extra.previewName,{},false
        p.wizard,p.customTheme,p.settings=nil,nil,nil
        if p.phase~="voting" then p.runwayOrder=nil end
    end
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
    info:SetHeight(150)
    votePanel:Hide()
    utility:Hide()
    extra.themeButton:Hide()
    extra.timerButton:Hide()
    extra.turnDeadline=nil
    extra.turnClock:SetText("")
    extra.themeInput:SetShown(extra.themeEditor==true)
    extra.viewButton:SetShown(p.practice==true and not preferencesMode and not extra.themeEditor and not extra.timerSetup)
    extra.viewButton:SetText(extra.previewName and "Host view" or "View as")
    prefsLink:SetShown(not p.preview and not extra.themeEditor and not extra.viewPicker and not extra.timerSetup)
    endOfTimer:SetText("")
    endOfTimer:SetAlpha(1)
    heroName:SetText("")
    heroNext:SetText("")
    applyPreferences()
    local phaseIndex=({preparation=2,runway=3,paused=3,runway_complete=3,voting=4,round_results=5})[p.phase]
    paintPhases(preferencesMode and 0 or phaseIndex or 1)
    decorate(overview,p.phase=="runway" and palette.selected or palette.panel,
        p.phase=="runway" and palette.trim or palette.outline)
    badge:SetText(p.preview and ("CONTESTANT VIEW  /  "..extra.previewName) or p.practice and "PRACTICE MODE  /  FICTIONAL ROSTER" or p.isLeader and "RAID LEADER CONSOLE"
        or p.localRole and p.localRole:upper() or "RAID FASHION CONTEST")
    brand:SetText("STRUT YOUR BOOTSY")
    primary:SetShown(true)
    list:SetShown(lobby == true or (p.phase == "runway" and p.runwayOrder ~= nil))
    contestant:SetShown(chooser == true)
    spectator:SetShown(chooser == true)
    confirmPassive:SetShown(lobby == true and not p.practice)
    skipPrep:SetShown(p.practice == true and not p.preview and p.phase == "preparation")
    secondary:SetText(p.preview and "Host view" or p.practice and "Exit practice" or lobby and "Cancel" or "Refresh")

    if extra.themeEditor then
        list:Hide();contestant:Hide();spectator:Hide();confirmPassive:Hide();skipPrep:Hide()
        title:SetText("Name your theme")
        summary:SetText("Only the raid leader sees the name before Start.")
        details:SetText("")
        roleHint:SetText("")
        actionLabel(primary,"Use theme",context.normalizeTheme(extra.themeInput:GetText())~=nil)
        actionLabel(secondary,"Cancel")
        actionLabel(utility,"Random theme")
        prompt=extra.themeFeedback or "Up to 48 characters. Start with a letter; use letters, numbers, spaces, commas, apostrophes or hyphens."
    elseif extra.timerSetup then
        contestant:Hide();spectator:Hide();confirmPassive:Hide();skipPrep:Hide()
        prompt=showRunwayTimer(p)
    elseif preferencesMode then
        contestant:Hide();spectator:Hide();confirmPassive:Hide();skipPrep:Hide()
        prompt=showPreferences()
    elseif extra.viewPicker then
        list:Hide();contestant:Hide();spectator:Hide();confirmPassive:Hide();skipPrep:Hide()
        title:SetText("View as a contestant")
        summary:SetText("Choose one of the fictional contestants.")
        details:SetText("");roleHint:SetText("")
        local options={}
        for _,m in ipairs(p.members) do
            local name=m.name
            options[#options+1]={name,function()
                extra.previewName,extra.previewSession,extra.viewPicker=name,p.sessionId,nil
                UI.Refresh()
            end}
        end
        optionRows(options)
        primary:Hide()
        actionLabel(secondary,"Back")
        prompt="This is a read-only preview. No one else sees it."
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
        if p.practice then actionLabel(utility,"Setup Contest") end
        actionLabel(extra.themeButton,"Theme...")
        if p.runwaySeconds then actionLabel(extra.timerButton,"Runway timer") end
        summary:SetText(("Contestants: %d / 5 minimum\nSpectators: %d\nPending addon responses: %d"):format(
            p.contestants, p.spectators, p.pendingResponses))
        details:SetText("Raid roster")
        roleHint:SetText("")
        updateRoster(p.members)
        confirmPassive:SetEnabled(selectedObserver ~= nil and p.discoveryComplete == true)
        primary:SetText("Start contest")
        primary:SetEnabled(p.lobbyState == "ready_to_start")
        prompt = p.lobbyState == "ready_to_start"
            and (p.customTheme and ("Theme selected, hidden until Start: "..p.customTheme)
                or p.practice and "Five fictional contestants. No raid messages are sent."
                or "Ready to start. The administrator does not compete or vote.")
            or (messages[p.lobbyState] or "Start is unavailable. Refresh the raid roster and check /syb status.")
    elseif chooser then
        local role = p.localRole or p.submittedRole or selectedRole
        title:SetText("Choose your role")
        summary:SetText("Your participation")

        local canChoose = not p.localRole and not p.awaiting and not p.timedOut
        contestant:SetEnabled(canChoose)
        spectator:SetEnabled(canChoose)
        paintSelection(contestant,role=="contestant")
        paintSelection(spectator,role=="spectator")
        details:SetText(role == "spectator" and "Spectator rules" or "Contestant rules")
        roleHint:SetText(role == "spectator" and "Watch the runway and vote each round." or
            "Present your outfit each round. Vote for others.")
        primary:SetText(p.timedOut and "Retry confirmation" or "Confirm role")
        primary:SetEnabled(role ~= nil and not p.localRole and not p.awaiting)
        if p.preview then prompt = "You’re registered as a contestant. Waiting for the raid leader."
        elseif p.localRole then prompt = "Registered as " .. p.localRole .. ". Awaiting the administrator."
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
        prepLimit=p.prepLimit
        primary:SetText("Begin runway")
        primary:SetShown(prepHost)
        primary:SetEnabled(false)
        prepDeadline = p.preparation and p.preparation.endsAt
        prompt = prepDeadline and "" or "Syncing the countdown with the raid leader…"
    elseif p.phase == "runway" and p.runway then
        local r = p.runway
        title:SetText(("Round %d of %d: Runway"):format(p.round or 1,p.rounds or 1))
        if p.practice and not p.preview then actionLabel(utility,"Pause") end
        summary:SetText(("Presenting  %d of %d"):format(r.index,r.total))
        heroName:SetText(r.current)
        heroNext:SetText(r.upcoming and "Up next: " .. r.upcoming or "Final presentation")
        extra.turnDeadline=r.endsAt
        UI.UpdateRunwayClock()
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
            roleHint:SetText(presenting(p) and "You’re presenting now." or p.preview and (r.current==extra.previewName and "Waiting for the runway to resume." or
                r.upcoming==extra.previewName and "You’re up next. Get ready." or "Waiting for the raid leader to advance.")
                or "The raid leader advances the runway.")
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
        prompt = not p.practice and p.isLeader
            and "Manual podium: /syb announce winners First Second Third" or ""
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
    if p.preview then
        primary:Hide()
        utility:Hide()
        skipPrep:Hide()
        actionLabel(secondary,"Host view")
    end
    updateEmoteDrawer(p)
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
