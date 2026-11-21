local addonName, ns = ...
local UI = {}
ns.UI = UI

local window
local statusText
local context = {}
local gold = { 0.88, 0.71, 0.42 }
local pale = { 0.92, 0.94, 0.96 }

local function label(parent, text, size, x, y, color)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    font:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    font:SetFont(STANDARD_TEXT_FONT, size)
    font:SetTextColor(unpack(color or pale))
    font:SetText(text)
    return font
end

local function button(parent, text, width, x, y, handler)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 29)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", handler)
    return b
end

local function build()
    window = CreateFrame("Frame", "SYBAdminWindow", UIParent, "BackdropTemplate")
    window:SetSize(465, 335)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    window:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    window:SetBackdropColor(0.067,0.094,0.129,0.98)
    window:SetBackdropBorderColor(unpack(gold))
    label(window, "STRUT YOUR BOOTSY", 13, 25, -23, gold)
    label(window, "Welcome to the runway", 20, 25, -53)
    label(window, "Raid fashion runway competition", 13, 25, -87, {0.62,0.68,0.74})
    local panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 24, -119)
    panel:SetSize(417, 122)
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    panel:SetBackdropColor(0.145,0.18,0.23,1)
    label(panel, "Contest status", 16, 16, -14)
    statusText = label(panel, "Checking raid status...", 13, 16, -45, {0.72,0.78,0.84})
    statusText:SetWidth(382)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(true)
    button(window, "Refresh", 95, 24, -259, function() UI.Refresh() end)
    local start = button(window, "Set up contest", 160, 281, -259, function()
        if context.say then context.say("Contest setup is not implemented in this milestone.") end
    end)
    start:Disable()
    start:SetScript("OnEnter", function() GameTooltip:SetOwner(start, "ANCHOR_TOP"); GameTooltip:SetText("Coming next: configuration and registration lobby"); GameTooltip:Show() end)
    start:SetScript("OnLeave", GameTooltip_Hide)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)
    window:Hide()
    table.insert(UISpecialFrames, "SYBAdminWindow")
end

function UI.Refresh()
    if not window then return end
    local inRaid = IsInRaid and IsInRaid()
    local projection = context.getProjection and context.getProjection()
    local status = inRaid and "In raid" or "Not in a raid"
    local leader = projection and projection.leader or "none"
    local session = projection and projection.sessionId or "none"
    statusText:SetText(status .. "\\nRaid leader: " .. tostring(leader or "none") ..
        "\\nNetwork session: " .. tostring(session or "none") ..
        "\\nAdmin setup and gameplay controls are not yet enabled.")
end

function UI.Toggle()
    if not window then build() end
    if window:IsShown() then window:Hide() else UI.Refresh(); window:Show() end
end

function UI.Initialize(options)
    context = options or {}
    local launcher = CreateFrame("Button", "SYBMinimapLauncher", Minimap)
    launcher:SetSize(30,30)
    launcher:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    launcher:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    launcher:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    launcher:SetScript("OnClick", UI.Toggle)
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Strut Your Bootsy")
        GameTooltip:AddLine("Click to open the contest window.", 1,1,1)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", GameTooltip_Hide)
end
