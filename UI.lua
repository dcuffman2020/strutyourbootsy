local addonName, ns = ...
local UI = {}
ns.UI = UI

local window, launcher
local brand, title, summary, details, status, actionNotice, roleHint, list, listContent
local primary, secondary, contestant, spectator, confirmPassive, skipPrep
local context = {}
local rows = {}
local selectedRole, selectedObserver, sessionId
local prepDeadline, prepSeconds, prepTick, prepHost, prepBlocked = nil, nil, 0, false, false
local gold = {0.88, 0.71, 0.42}
local pale = {0.92, 0.94, 0.96}
local muted = {0.62, 0.68, 0.74}
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
    font:SetText(text)
    if width then
        font:SetWidth(width)
        font:SetJustifyH("LEFT")
        font:SetWordWrap(true)
    end
    return font
end

local function button(parent, text, width, x, y, handler)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 28)
    control:SetPoint("TOPLEFT", x, y)
    control:SetText(text)
    control:SetScript("OnClick", handler)
    return control
end

local function panel(y, height)
    local control = CreateFrame("Frame", nil, window, "BackdropTemplate")
    control:SetPoint("TOPLEFT", 28, y)
    control:SetSize(409, height)
    control:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    control:SetBackdropColor(0.145, 0.18, 0.23, 1)
    return control
end

local function refreshPreparationClock()
    if not prepDeadline then return end
    local remaining = math.min(context.preparationSeconds, math.max(0, prepDeadline - context.serverNow()))
    if remaining == prepSeconds then return end
    prepSeconds = remaining
    if prepHost then primary:SetEnabled(remaining == 0 and not prepBlocked) end
    if remaining > 0 then
        status:SetText(("Time to prepare: %d:%02d"):format(math.floor(remaining / 60), remaining % 60))
    else
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
    window:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12,
        insets={left=3, right=3, top=3, bottom=3}})
    window:SetBackdropColor(0.067, 0.094, 0.129, 0.98)
    window:SetBackdropBorderColor(unpackColor(gold))
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetScript("OnHide", window.StopMovingOrSizing)
    window:SetScript("OnUpdate", function(_, elapsed)
        if not prepDeadline or prepSeconds == 0 then return end
        prepTick = prepTick + elapsed
        if prepTick < 0.25 then return end
        prepTick = 0
        refreshPreparationClock()
    end)

    brand = label(window, "STRUT YOUR BOOTSY", 14, 28, -25, gold)
    title = label(window, "Welcome to the runway", 24, 28, -56)
    local overview = panel(-99, 111)
    summary = label(overview, "", 14, 18, -16, pale, 372)
    contestant = button(overview, "Contestant", 132, 18, -64, function()
        selectedRole = "contestant"
        UI.Refresh()
    end)
    spectator = button(overview, "Spectator", 132, 158, -64, function()
        selectedRole = "spectator"
        UI.Refresh()
    end)

    local info = panel(-225, 154)
    details = label(info, "", 14, 18, -14, muted, 370)
    roleHint = label(info, "", 14, 18, -47, muted, 370)
    list = CreateFrame("ScrollFrame", "SYBRegistrationRosterScroll", info, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", 17, -42)
    list:SetSize(351, 98)
    listContent = CreateFrame("Frame", nil, list)
    listContent:SetSize(351, 98)
    list:SetScrollChild(listContent)

    actionNotice = label(window, "", 13, 29, -392, muted, 398)
    status = label(window, "", 14, 29, -436, gold, 398)
    primary = button(window, "Open registration", 152, 285, -485, function()
        local p = context.getProjection()
        if p.isLeader then
            if p.sessionId and p.phase == "registration" then context.start()
            elseif p.phase == "preparation" then context.beginRunway()
            elseif p.phase == "runway" then context.advanceRunway()
            elseif p.phase == "runway_complete" and p.practice then context.restartPractice()
            else context.openRegistration() end
        else
            context.submitRole(p.submittedRole or selectedRole)
        end
    end)
    secondary = button(window, "Refresh", 101, 28, -485, function()
        local p = context.getProjection()
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
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)
    window:Hide()
    table.insert(UISpecialFrames, "SYBAdminWindow")
end

local function updateRoster(members, runway)
    local pitch, height = runway and 24 or 26, runway and 120 or 98
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", 17, runway and -30 or -42)
    list:SetSize(351, height)
    local stillSelected
    for index, member in ipairs(members) do
        local row = rows[index]
        if not row then
            row = button(listContent, "", 347, 0, -(index - 1) * 26, function(self)
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
            -- Text is read-only, but stays legible instead of using the disabled skin.
            row:SetEnabled(true)
            row:EnableMouse(false)
        else
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
    brand:SetText(p.practice and "STRUT YOUR BOOTSY  ·  PRACTICE MODE" or "STRUT YOUR BOOTSY")
    primary:SetShown(true)
    list:SetShown(lobby == true or (p.phase == "runway" and p.runwayOrder ~= nil))
    contestant:SetShown(chooser == true)
    spectator:SetShown(chooser == true)
    confirmPassive:SetShown(lobby == true and not p.practice)
    skipPrep:SetShown(p.practice == true and p.phase == "preparation")
    secondary:SetText(p.practice and "Exit practice" or lobby and "Cancel" or "Refresh")

    if lobby then
        title:SetText("Registration lobby")
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
        title:SetText("Round 1 of 1: Preparation")
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
        primary:SetText("Begin runway")
        primary:SetShown(prepHost)
        primary:SetEnabled(false)
        prepDeadline = p.preparation and p.preparation.endsAt
        prompt = prepDeadline and "" or "Syncing the countdown with the raid leader…"
    elseif p.phase == "runway" and p.runway then
        local r = p.runway
        title:SetText("Round 1 of 1: Runway")
        summary:SetText(("Presenting  %d of %d\n%s\n%s"):format(r.index,r.total,r.current,
            r.upcoming and "Up next: " .. r.upcoming or "Final presentation"))
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
        details:SetText("End of this test build")
        roleHint:SetText("Voting is not included yet.")
        primary:SetText("Practice again")
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
