local addonName, ns = ...
local UI = {}
ns.UI = UI

local window, launcher
local title, summary, details, status, roleHint, list, listContent
local primary, secondary, contestant, spectator, confirmPassive
local context = {}
local rows = {}
local selectedRole, selectedObserver, sessionId
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

local function build()
    window = CreateFrame("Frame", "SYBAdminWindow", UIParent, "BackdropTemplate")
    window:SetSize(465, 506)
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

    label(window, "STRUT YOUR BOOTSY", 14, 28, -25, gold)
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

    status = label(window, "", 14, 29, -392, gold, 398)
    primary = button(window, "Open registration", 152, 285, -457, function()
        local p = context.getProjection()
        if p.isLeader then
            if p.sessionId and p.phase == "registration" then context.start()
            else context.openRegistration() end
        else
            context.submitRole(p.submittedRole or selectedRole)
        end
    end)
    secondary = button(window, "Refresh", 101, 28, -457, function()
        local p = context.getProjection()
        if p.isLeader and p.sessionId and p.phase == "registration" then context.cancel()
        else context.refresh() end
    end)
    confirmPassive = button(window, "Confirm no addon", 140, 135, -457, function()
        if selectedObserver then context.confirmPassive(selectedObserver.name, selectedObserver.guid) end
    end)
    confirmPassive:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Confirm only after checking with this player that the addon is absent.")
        GameTooltip:Show()
    end)
    confirmPassive:SetScript("OnLeave", GameTooltip_Hide)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)
    window:Hide()
    table.insert(UISpecialFrames, "SYBAdminWindow")
end

local function updateRoster(members)
    local stillSelected
    for index, member in ipairs(members) do
        local row = rows[index]
        if not row then
            row = button(listContent, "", 347, 0, -(index - 1) * 26, function(self)
                selectedObserver = self.member
                UI.Refresh()
            end)
            row:SetHeight(25)
            rows[index] = row
        end
        row.member = member
        local selected = selectedObserver and selectedObserver.guid == member.guid
        if selected and member.presence == "unknown" then stillSelected = member end
        local role = member.role and (" / " .. member.role) or ""
        row:SetText((selected and "> " or "") .. member.name .. "  " .. presenceLabels[member.presence] .. role)
        row:SetEnabled(member.presence == "unknown")
        row:Show()
    end
    for i = #members + 1, #rows do rows[i]:Hide() end
    listContent:SetHeight(math.max(98, #members * 26))
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
    list:SetShown(lobby == true)
    contestant:SetShown(chooser == true)
    spectator:SetShown(chooser == true)
    confirmPassive:SetShown(lobby == true)
    secondary:SetText(lobby and "Cancel" or "Refresh")

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
        prompt = messages[p.lobbyState] or "Ready to start. The administrator does not compete or vote."
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
    else
        title:SetText("Welcome to the runway")
        summary:SetText((IsInRaid() and "In raid" or "Not in a raid. Join a raid to participate.") ..
            "\nRaid leader: " .. (p.leader or "none"))
        details:SetText("Contest status")
        roleHint:SetText(p.phase == "preparation" and "The contest has started. Registration is closed." or
            p.phase == "ended" and "The raid registration session ended." or
            registration and "Raid registration is open." or "No active contest.")
        primary:SetText("Open registration")
        primary:SetEnabled(p.isLeader == true and (not p.sessionId or p.phase == "ended"))
        prompt = (registration or p.lobbyState == "late_joiner") and messages[p.lobbyState] or ""
    end
    status:SetText(p.notice and (messages[p.notice] or ("Action failed (" .. p.notice .. "). Refresh and try again.")) or prompt)
end

function UI.Toggle()
    if not window then build() end
    if window:IsShown() then window:Hide() else window:Show(); UI.Refresh() end
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
    launcher:SetNormalTexture("Interface\\Icons\\INV_Boots_05")
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
