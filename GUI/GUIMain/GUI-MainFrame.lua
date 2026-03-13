-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local math = math

-- Sidebar configuration
GUIFrame.sidebarConfig = {
    {
        id = "profiles_section",
        type = "header",
        text = "\226\128\162 Profiles",
        defaultExpanded = true,
        items = {
            { id = "Profiles", text = "Profile Manager" },
        },
    },
    {
        id = "optimize_section",
        type = "header",
        text = "\226\128\162 Optimize",
        defaultExpanded = true,
        items = {
            { id = "Optimize", text = "System Optimization" },
        },
    },
    {
        id = "combat_section",
        type = "header",
        text = "\226\128\162 Combat",
        defaultExpanded = true,
        items = {
            { id = "CombatTimer",   text = "Combat Timer" },
            { id = "CombatCross",   text = "Combat Cross" },
            { id = "CombatRes",     text = "Combat Res" },
            { id = "CombatTexts",   text = "Combat Texts" },
            { id = "RangeChecker",  text = "Range Checker Text" },
            { id = "PetStatusText", text = "Pet Status Texts" },
            { id = "GatewayAlert",  text = "Gateway Alert" },
            { id = "TargetCastbar", text = "Target Castbar" },
            { id = "FocusCastbar",  text = "Focus Castbar" },
            { id = "TimeSpiral",    text = "Time Spiral" },
        },
    },
    {
        id = "qol_section",
        type = "header",
        text = "\226\128\162 Quality of Life",
        defaultExpanded = true,
        items = {
            { id = "Automation",    text = "Automation" },
            { id = "CVars",         text = "CVars" },
            { id = "SlashCommands", text = "Slash Commands" },
            { id = "CursorCircle",  text = "Cursor Circle" },
            { id = "MissingBuffs",  text = "Missing Buffs" },
            { id = "HuntersMark",   text = "Hunter's Mark Missing" },
            { id = "DragonRiding",  text = "Dragon Riding UI" },
            { id = "CopyAnything",  text = "Copy Anything" },
            { id = "HideBars",      text = "Hide ActionBars" },
            { id = "Recuperate",    text = "Recuperate Button" },
        },
    },
    {
        id = "skinning_section",
        type = "header",
        text = "\226\128\162 Skinning",
        defaultExpanded = true,
        elvUIDisabled = true,
        items = {
            { id = "SkinUICleanup",    text = "General UI Clean Up" },
            { id = "SkinAuras",        text = "Buffs, Debuffs & Externals" },
            { id = "SkinActionBars",   text = "Action Bars" },
            { id = "SkinMicroMenu",    text = "Micro Menu" },
            { id = "SkinMouseover",    text = "Blizzard Mouseover" },
            { id = "SkinMessages",     text = "Blizzard Texts" },
            { id = "SkinTooltips",     text = "Blizzard Tooltips" },
            { id = "SkinDetails",      text = "Details Backdrop" },
            { id = "SkinRaidManager",  text = "Raid Manager Panel" },
        },
    },
    {
        id = "custombuffs_section",
        type = "header",
        text = "\226\128\162 Custom Buffs",
        defaultExpanded = true,
        items = {
            { id = "ExternalsDefensives", text = "Personal Defensives" },
            { id = "MovementBuffs",       text = "Personal Movement Buffs" },
            { id = "BuffIcons",           text = "Buff Icons" },
            { id = "BuffBars",            text = "Buff Bars" },
        },
    },
}

--------------------------------------------------------------------------------
-- Create Content Area (right panel with scroll frame)
--------------------------------------------------------------------------------
function GUIFrame:CreateContentArea(parent)
    local T = Theme

    local content = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    content:SetWidth(T.contentWidth)
    content:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -T.borderSize, -(T.headerHeight + T.borderSize))
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -T.borderSize, T.borderSize)

    content:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    content:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    -- Style scrollbar
    local scrollbarWidth = T.scrollbarWidth or 14
    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", content, "TOPRIGHT", -3, -T.paddingSmall - 12)
        sb:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -3, T.paddingSmall + 12)
        sb:SetWidth(scrollbarWidth - 4)
        if sb.Background then sb.Background:Hide() end
        if sb.Top then sb.Top:Hide() end
        if sb.Middle then sb.Middle:Hide() end
        if sb.Bottom then sb.Bottom:Hide() end
        if sb.trackBG then sb.trackBG:Hide() end
        if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetAlpha(0)
    end

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Scrollbar visibility
    local scrollbarVisible = false
    local function UpdateScrollChildWidth()
        if scrollbarVisible then
            scrollChild:SetWidth(T.contentWidth - scrollbarWidth)
        else
            scrollChild:SetWidth(T.contentWidth)
        end
    end

    local function UpdateScrollBarVisibility()
        if scrollFrame.ScrollBar then
            local contentH = scrollChild:GetHeight()
            local frameH = scrollFrame:GetHeight()
            local needsScrollbar = contentH > frameH
            scrollbarVisible = needsScrollbar
            scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
            UpdateScrollChildWidth()
        end
    end

    content.UpdateScrollBarVisibility = UpdateScrollBarVisibility

    scrollFrame:HookScript("OnScrollRangeChanged", UpdateScrollBarVisibility)
    scrollChild:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateScrollBarVisibility)
    end)
    content:SetScript("OnSizeChanged", function()
        UpdateScrollChildWidth()
    end)

    -- Initial width (deferred so content has resolved its size)
    C_Timer.After(0, UpdateScrollChildWidth)

    content.scrollFrame = scrollFrame
    content.scrollChild = scrollChild
    parent.content = content
    self.contentArea = content
    return content
end

--------------------------------------------------------------------------------
-- Create the main GUI frame
--------------------------------------------------------------------------------
function GUIFrame:CreateMainFrame()
    if self.mainFrame then return end

    local T = Theme

    local frame = CreateFrame("Frame", "KE_GUIFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(870, 800)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(810, 550)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = f:GetPoint()
        if KE.db and KE.db.global then
            KE.db.global.GUIState.frame.point = point
            KE.db.global.GUIState.frame.relativePoint = relativePoint
            KE.db.global.GUIState.frame.xOffset = xOfs
            KE.db.global.GUIState.frame.yOffset = yOfs
        end
    end)

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = T.borderSize,
    })
    frame:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
    frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Title bar
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(T.headerHeight)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", T.borderSize, -T.borderSize)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -T.borderSize, -T.borderSize)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetPoint("LEFT", header, "LEFT", T.paddingMedium, 0)
    KE:ApplyThemeFont(title, "normal")
    title:SetText(KE:ColorTextByTheme("Kitn") .. "Essentials")

    -- Close button (custom cross texture)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    closeBtn:SetScript("OnClick", function() GUIFrame:Hide() end)
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAllPoints()
    closeIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png")
    closeIcon:SetRotation(math.rad(45))
    closeIcon:SetVertexColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], T.textPrimary[4])
    closeBtn:SetScript("OnEnter", function()
        closeIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeIcon:SetVertexColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], T.textPrimary[4])
    end)

    -- Home button (custom texture)
    local homeBtn = CreateFrame("Button", nil, header)
    homeBtn:SetSize(18, 18)
    homeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    local homeIcon = homeBtn:CreateTexture(nil, "ARTWORK")
    homeIcon:SetAllPoints()
    homeIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\HomeButtonv2.png")
    homeIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    homeBtn:SetScript("OnEnter", function()
        homeIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    homeBtn:SetScript("OnLeave", function()
        homeIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    end)
    homeBtn:SetScript("OnClick", function()
        GUIFrame:SelectSidebarItem("HomePage")
    end)

    -- Header bottom border
    local headerBorder = header:CreateTexture(nil, "BORDER")
    headerBorder:SetHeight(T.borderSize)
    headerBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Close on ESC
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            GUIFrame:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame:EnableKeyboard(true)

    -- Restore saved position and size
    if KE.db and KE.db.global and KE.db.global.GUIState.frame.point then
        local gs = KE.db.global.GUIState.frame
        frame:ClearAllPoints()
        frame:SetPoint(gs.point, UIParent, gs.relativePoint, gs.xOffset, gs.yOffset)
        if gs.width and gs.height then
            frame:SetSize(gs.width, gs.height)
        end
    end

    frame:Hide()
    self.mainFrame = frame
    self.header = header
    self.title = title

    -- Overlay for dropdowns (renders above content)
    KE.GUIOverlay = CreateFrame("Frame", nil, UIParent)
    KE.GUIOverlay:SetAllPoints(UIParent)
    KE.GUIOverlay:SetFrameStrata("TOOLTIP")
    KE.GUIOverlay:SetFrameLevel(1)
    KE.GUIOverlay:EnableMouse(false)

    -- Create sidebar and content area
    self:CreateContentArea(frame)
    self:CreateSidebar(frame)

    -- Bottom bar (version text + resize handle)
    local bottomBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bottomBar:SetHeight(T.footerHeight)
    bottomBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", T.borderSize, T.borderSize)
    bottomBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.borderSize, T.borderSize)
    bottomBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    bottomBar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    -- Top border on the bottom bar
    local bottomBarBorder = bottomBar:CreateTexture(nil, "OVERLAY")
    bottomBarBorder:SetHeight(T.borderSize)
    bottomBarBorder:SetPoint("TOPLEFT", bottomBar, "TOPLEFT", 0, 0)
    bottomBarBorder:SetPoint("TOPRIGHT", bottomBar, "TOPRIGHT", 0, 0)
    bottomBarBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Version text (left side)
    local versionText = bottomBar:CreateFontString(nil, "OVERLAY")
    versionText:SetPoint("LEFT", bottomBar, "LEFT", T.paddingSmall, 0)
    KE:ApplyThemeFont(versionText, "small")
    versionText:SetText(KE:ColorTextByTheme("Kitn") .. "Essentials |cff888888v" .. (KE.Version or "?") .. "|r")

    -- Resize grip (right side, custom texture)
    local resizeGrip = CreateFrame("Button", nil, bottomBar)
    resizeGrip:SetSize(23, 23)
    resizeGrip:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", 0, 0)
    local resizeTex = resizeGrip:CreateTexture(nil, "ARTWORK")
    resizeTex:SetAllPoints()
    resizeTex:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomResizeHandle23px.png")
    resizeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnDragStart", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if KE.db and KE.db.global then
            KE.db.global.GUIState.frame.width = frame:GetWidth()
            KE.db.global.GUIState.frame.height = frame:GetHeight()
        end
    end)
    resizeGrip:SetScript("OnEnter", function()
        resizeTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.8)
    end)
    resizeGrip:SetScript("OnLeave", function()
        resizeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)
    end)

    -- Adjust content area to account for bottom bar
    if self.contentArea then
        self.contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.borderSize, T.footerHeight)
    end
end

-- Combat handling: Close GUI on entering combat, reopen on leaving combat
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if GUIFrame:IsShown() then
            GUIFrame.reopenAfterCombat = true
            GUIFrame:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if GUIFrame.reopenAfterCombat then
            GUIFrame.reopenAfterCombat = nil
            GUIFrame:Show()
        end
    end
end)
