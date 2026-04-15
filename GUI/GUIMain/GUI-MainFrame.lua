-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MainFrame.lua                                       ║
-- ║  Purpose: Main settings frame, sidebar navigation,       ║
-- ║  and content area.                                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local math = math

---------------------------------------------------------------------------------
-- Sidebar Data
---------------------------------------------------------------------------------

-- Sidebar configuration
GUIFrame.sidebarConfig = {
    {
        id = "settings_section",
        type = "header",
        text = "\226\128\162 Settings",
        defaultExpanded = true,
        items = {
            { id = "Profiles", text = "Profile Manager" },
            { id = "Theme",    text = "Addon Theme" },
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
            { id = "CombatRes",     text = "Battle Res" },
            { id = "BossDebuffs",   text = "Boss Debuffs" },
            { id = "CombatTexts",   text = "Combat Texts" },
            { id = "CombatTimer",   text = "Combat Timer" },
            { id = "CursorCircle",  text = "Cursor Circle" },
            { id = "Castbars",      text = "Focus & Target Castbar" },
            { id = "CombatCross",   text = "Player Crosshair" },
            { id = "RangeChecker",  text = "Range Display" },
        },
    },
    {
        id = "utilities_section",
        type = "header",
        text = "\226\128\162 Utilities",
        defaultExpanded = true,
        items = {
            { id = "BloodlustTracker", text = "Bloodlust Tracker" },
            { id = "ClassStatusTexts", text = "Class Status Texts" },
            { id = "PotionReady",   text = "Combat Potion Ready" },
            { id = "EvokerSuite",   text = "Evoker Suite" },
            { id = "MacroBuilders", text = "Macro Builders" },
            { id = "RaidNotifications", text = "Raid Notifications" },
            { id = "Recuperate",    text = "Recuperate Button" },
            { id = "TimeSpiral",    text = "Time Spiral Tracker" },
            { id = "WorldMarkerCycler", text = "World Marker Cycler" },
        },
    },
    {
        id = "qol_section",
        type = "header",
        text = "\226\128\162 Quality of Life",
        defaultExpanded = true,
        items = {
            { id = "AuctionHouseFilter", text = "Auction House Filter" },
            { id = "Automation",        text = "Automation" },
            { id = "CombatLogger",      text = "Combat Logger" },
            { id = "CopyAnything",      text = "Copy Anything" },
            { id = "CVars",             text = "CVars" },
            { id = "GreatVaultAlert",   text = "Great Vault Alert" },
            { id = "HideBars",          text = "Hide ActionBars" },
            { id = "HuntersMark",       text = "Hunter's Mark Missing" },
            { id = "MissingEnchants",   text = "Missing Enchants/Gems" },
            { id = "RacialsAnchor",     text = "Racials Anchor" },
            { id = "DragonRiding",      text = "Skyriding UI" },
            { id = "SlashCommands",     text = "Slash Commands" },
            { id = "WorldMap",          text = "World Map Scaler" },
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
            { id = "SkinBattlenet",    text = "Battle.net Toast" },
            { id = "SkinMouseover",    text = "Blizzard Mouseover" },
            { id = "SkinMessages",     text = "Blizzard Texts" },
            { id = "SkinTooltips",     text = "Blizzard Tooltips" },
            { id = "SkinMicroMenu",    text = "Micro Menu" },
            { id = "SkinDetails",      text = "Details Backdrop" },
            { id = "SkinRaidManager",  text = "Raid Manager Panel" },
        },
    },
    {
        id = "dungeons_section",
        type = "header",
        text = "\226\128\162 Dungeons",
        defaultExpanded = true,
        items = {
            { id = "WarpDepleteForces",           text = "WarpDeplete+" },
            { id = "EnemyCounter",                text = "Enemy Counter" },
            { id = "KickTracker",                 text = "Interrupt Tracker" },
            { id = "DungeonCasts",                text = "Dungeon Casts" },
        },
    },
    {
        id = "dungeon_timers_section",
        type = "header",
        text = "\226\128\162 Dungeon Timers",
        defaultExpanded = true,
        disabledCheck = function()
            return not (KE.db and KE.db.profile and KE.db.profile.Dungeons
                and KE.db.profile.Dungeons.DungeonTimers
                and KE.db.profile.Dungeons.DungeonTimers.Enabled)
        end,
        items = {
            { id = "Dungeon_Settings",            text = "Timers Settings", alwaysEnabled = true },
            { id = "Dungeon_AlgetharAcademy",     text = "Algeth'ar Academy" },
            { id = "Dungeon_MagistersTerrace",    text = "Magisters' Terrace" },
            { id = "Dungeon_MaisaraCaverns",      text = "Maisara Caverns" },
            { id = "Dungeon_NexusPointXenas",     text = "Nexus-Point Xenas" },
            { id = "Dungeon_PitOfSaron",          text = "Pit of Saron" },
            { id = "Dungeon_SeatOfTriumvirate",   text = "Seat of the Triumvirate" },
            { id = "Dungeon_Skyreach",            text = "Skyreach" },
            { id = "Dungeon_WindrunnerSpire",      text = "Windrunner Spire" },
        },
    },
}

---------------------------------------------------------------------------------
-- Content Area
---------------------------------------------------------------------------------
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

    -- Smooth mousewheel scrolling
    local SCROLL_STEP = 40
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if scrollFrame.ScrollBar then
            local sb = scrollFrame.ScrollBar
            local current = sb:GetValue()
            local minVal, maxVal = sb:GetMinMaxValues()
            local newValue = current - (delta * SCROLL_STEP)
            if newValue < minVal then newValue = minVal end
            if newValue > maxVal then newValue = maxVal end
            sb:SetValue(newValue)
        end
    end)

    -- Scroll child. Initial width set synchronously so content builders never
    -- see a zero-width parent (the existing deferred UpdateScrollChildWidth
    -- below still runs to handle scrollbar width adjustments later).
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollChild:SetWidth(T.contentWidth)
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

---------------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------------
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
    frame:SetResizeBounds(945, 550)
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
    KE:ApplyThemeFont(title, "large")
    title:SetText(KE:ColorTextByTheme("Kitn") .. "Essentials")
    GUIFrame.titleText = title

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

    -- Hamburger menu button
    local menuBtn = CreateFrame("Button", nil, header)
    menuBtn:SetSize(18, 18)
    menuBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    local menuIcon = menuBtn:CreateTexture(nil, "ARTWORK")
    menuIcon:SetAllPoints()
    menuIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomBurger.png")
    menuIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    menuBtn:SetNormalTexture(menuIcon)
    menuIcon:SetTexelSnappingBias(0)
    menuIcon:SetSnapToPixelGrid(true)

    -- Dropdown panel
    local ITEM_HEIGHT = 26
    local menuDropdown = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    menuDropdown:SetWidth(160)
    menuDropdown:SetFrameStrata("TOOLTIP")
    menuDropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    menuDropdown:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    menuDropdown:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    menuDropdown:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
    menuDropdown:Hide()
    GUIFrame.menuDropdown = menuDropdown

    local menuShortcuts = {
        { text = "Reload UI", onClick = function() ReloadUI() end },
        { text = "Blizzard Edit Mode", onClick = function()
            if EditModeManagerFrame and not EditModeManagerFrame:IsShown() then
                ShowUIPanel(EditModeManagerFrame)
            end
        end },
        { text = "Kitn Edit Mode", onClick = function()
            if KE.EditMode then
                KE.EditMode:Toggle()
            end
        end },
        { text = "Cooldown Manager", onClick = function()
            local cdFrame = _G["CooldownViewerSettings"]
            if cdFrame then
                cdFrame:Show()
                cdFrame:Raise()
            else
                KE:Print("CooldownViewerSettings not found. Enable Cooldown Manager in Edit Mode.")
            end
        end },
    }

    menuDropdown:SetHeight(#menuShortcuts * ITEM_HEIGHT)

    local menuItemTexts = {}

    for i, item in ipairs(menuShortcuts) do
        local btn = CreateFrame("Button", nil, menuDropdown, "BackdropTemplate")
        btn:SetHeight(ITEM_HEIGHT)
        btn:SetPoint("TOPLEFT", menuDropdown, "TOPLEFT", 0, -(i - 1) * ITEM_HEIGHT)
        btn:SetPoint("RIGHT", menuDropdown, "RIGHT", 0, 0)

        local btnText = btn:CreateFontString(nil, "OVERLAY")
        btnText:SetPoint("LEFT", btn, "LEFT", 8, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btnText:SetJustifyH("LEFT")
        KE:ApplyThemeFont(btnText, "normal")
        btnText:SetText(item.text)
        local Th = KE.Theme
        btnText:SetTextColor(Th.accent[1], Th.accent[2], Th.accent[3])

        btn:SetScript("OnClick", function()
            item.onClick()
            menuDropdown:Hide()
        end)
        btn:SetScript("OnEnter", function()
            local L = KE.Theme
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            btn:SetBackdropBorderColor(L.border[1], L.border[2], L.border[3], 1)
            btn:SetBackdropColor(L.accentHover[1], L.accentHover[2], L.accentHover[3], L.accentHover[4] or 0.25)
            btnText:SetTextColor(L.textPrimary[1], L.textPrimary[2], L.textPrimary[3], 1)
        end)
        btn:SetScript("OnLeave", function()
            local L = KE.Theme
            btn:SetBackdrop(nil)
            btnText:SetTextColor(L.accent[1], L.accent[2], L.accent[3])
            C_Timer.After(0.3, function()
                if menuDropdown:IsShown() and not menuDropdown:IsMouseOver() and not menuBtn:IsMouseOver() then
                    menuDropdown:Hide()
                end
            end)
        end)
        menuItemTexts[#menuItemTexts + 1] = btnText
    end

    -- Refresh item text colors on show (picks up current theme)
    menuDropdown:SetScript("OnShow", function()
        local L = KE.Theme
        menuDropdown:SetBackdropColor(L.bgMedium[1], L.bgMedium[2], L.bgMedium[3], 1)
        menuDropdown:SetBackdropBorderColor(L.border[1], L.border[2], L.border[3], 1)
        for _, txt in ipairs(menuItemTexts) do
            txt:SetTextColor(L.accent[1], L.accent[2], L.accent[3])
        end
    end)

    -- Open dropdown on hover
    menuBtn:SetScript("OnEnter", function()
        local L = KE.Theme
        menuIcon:SetVertexColor(L.accent[1], L.accent[2], L.accent[3], 1)
        menuDropdown:Show()
    end)
    menuBtn:SetScript("OnLeave", function()
        local L = KE.Theme
        menuIcon:SetVertexColor(L.textSecondary[1], L.textSecondary[2], L.textSecondary[3], 1)
        C_Timer.After(0.3, function()
            if not menuDropdown:IsMouseOver() and not menuBtn:IsMouseOver() then
                menuDropdown:Hide()
            end
        end)
    end)

    -- Close dropdown when mouse leaves
    menuDropdown:SetScript("OnLeave", function()
        C_Timer.After(0.3, function()
            if not menuDropdown:IsMouseOver() and not menuBtn:IsMouseOver() then
                menuDropdown:Hide()
            end
        end)
    end)

    -- Theme button (paint icon)
    local themeBtn = CreateFrame("Button", nil, header)
    themeBtn:SetSize(18, 18)
    themeBtn:SetPoint("RIGHT", menuBtn, "LEFT", -8, 0)
    local themeIcon = themeBtn:CreateTexture(nil, "ARTWORK")
    themeIcon:SetAllPoints()
    themeIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\fill.png")
    themeIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    themeBtn:SetNormalTexture(themeIcon)
    themeIcon:SetTexelSnappingBias(0)
    themeIcon:SetSnapToPixelGrid(true)
    themeBtn:SetScript("OnEnter", function()
        themeIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    themeBtn:SetScript("OnLeave", function()
        themeIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    end)
    themeBtn:SetScript("OnClick", function()
        GUIFrame:SelectSidebarItem("Theme")
    end)

    -- Home button (custom texture)
    local homeBtn = CreateFrame("Button", nil, header)
    homeBtn:SetSize(18, 18)
    homeBtn:SetPoint("RIGHT", themeBtn, "LEFT", -8, 0)
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

    -- Close on ESC (clear search first if focused)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            if GUIFrame.searchEditBox and GUIFrame.searchEditBox:HasFocus() then
                GUIFrame.searchEditBox:SetText("")
                GUIFrame.searchEditBox:ClearFocus()
            else
                GUIFrame:Hide()
            end
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
    GUIFrame.versionText = versionText

    -- Resize grip (right side, custom texture)
    local resizeGrip = CreateFrame("Button", nil, bottomBar)
    resizeGrip:SetSize(23, 23)
    resizeGrip:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", 0, 0)
    local resizeTex = resizeGrip:CreateTexture(nil, "ARTWORK")
    resizeTex:SetAllPoints()
    resizeTex:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomResizeHandle23px.png")
    resizeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if KE.db and KE.db.global then
            KE.db.global.GUIState.frame.width = frame:GetWidth()
            KE.db.global.GUIState.frame.height = frame:GetHeight()
        end
    end)
    resizeGrip:SetScript("OnDragStart", function() end)
    resizeGrip:SetScript("OnDragStop", function() end)
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

---------------------------------------------------------------------------------
-- Page Rendering
---------------------------------------------------------------------------------

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
