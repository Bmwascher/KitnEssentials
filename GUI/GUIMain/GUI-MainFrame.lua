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
            { id = "Profiles", text = "Profile Manager", keywords = { "profile", "profiles", "import", "export", "copy", "reset" } },
            { id = "Theme",    text = "Addon Theme", keywords = { "theme", "color", "accent", "appearance", "skin" } },
        },
    },
    {
        id = "optimize_section",
        type = "header",
        text = "\226\128\162 Optimize",
        defaultExpanded = false,
        items = {
            { id = "Optimize", text = "System Optimization", keywords = { "optimize", "performance", "fps", "cpu", "memory", "latency", "cvar" } },
        },
    },
    {
        id = "combat_section",
        type = "header",
        text = "\226\128\162 Combat Utilities",
        defaultExpanded = false,
        items = {
            { id = "AuraDebuffs",   text = "Advanced Debuffs", keywords = { "debuff", "debuffs", "aura", "boss", "dot", "magic", "curse", "poison", "disease" } },
            { id = "CombatRes",     text = "Battle Res", keywords = { "battle res", "brez", "combat res", "resurrect", "raid res", "cr" } },
            { id = "CombatTexts",   text = "Combat Texts", keywords = { "combat text", "scrolling", "no target", "interrupt", "durability" } },
            { id = "CombatTimer",   text = "Combat Timer", keywords = { "combat timer", "encounter", "duration", "stopwatch", "fight length" } },
            { id = "Cursor",        text = "Cursor Effects", keywords = { "cursor", "mouse", "pointer", "trail", "circle", "dispel", "cleanse", "purge", "magic", "curse", "poison", "disease", "debuff", "taunt" } },
            { id = "DamageMeter",   text = "Damage Meter", keywords = { "damage meter", "dps", "damage", "healing", "threat", "meter", "recount", "details" } },
            { id = "AuraExternals", text = "External and Defensive Buffs", keywords = { "external", "externals", "defensive", "buff", "cooldown", "mitigation" } },
            { id = "FocusCastbar",  text = "Focus Castbar", keywords = { "castbar", "cast", "focus", "casting", "interrupt" } },
            { id = "CombatCross",   text = "Player Crosshair", keywords = { "crosshair", "cross", "aim", "reticle", "player" } },
            { id = "RangeChecker",  text = "Range Display", keywords = { "range", "distance", "yards", "melee", "ranged" } },
        },
    },
    {
        id = "class_section",
        type = "header",
        text = "\226\128\162 Class Utilities",
        defaultExpanded = false,
        items = {
            { id = "EvokerSuite",   text = "Evoker Suite", keywords = { "evoker", "dragon", "empower", "ebon might", "prescience", "disintegrate", "augmentation", "devastation", "preservation" } },
            { id = "HuntersMark",   text = "Hunter: Mark Missing", keywords = { "hunter", "hunters mark", "mark", "marksman", "beast mastery", "survival" } },
            { id = "PetStatusText", text = "Pet Status Texts", keywords = { "pet", "status", "hunter", "warlock", "demon", "summon" } },
            { id = "PIMacroBuilder", text = "Priest: PI Macro", keywords = { "priest", "power infusion", "pi", "macro", "builder", "trinket", "racial", "potion" } },
            { id = "SpellAlerts",   text = "Spell Alert Opacity", keywords = { "spell alert", "opacity", "proc", "alert", "glow", "overlay" } },
            { id = "StanceText",    text = "Stance Text", keywords = { "stance", "form", "shapeshift", "druid", "warrior", "evoker", "presence" } },
            { id = "TotemTracker",  text = "Totem Tracker", keywords = { "totem", "totems", "shaman", "evoker" } },
            { id = "BurningRush",   text = "Warlock: Burning Rush", keywords = { "warlock", "burning rush", "movement", "speed" } },
        },
    },
    {
        id = "utilities_section",
        type = "header",
        text = "\226\128\162 General Utilities",
        defaultExpanded = false,
        items = {
            { id = "PotionReady",   text = "Combat Potion Ready", keywords = { "potion", "pot", "combat", "consumable" } },
            { id = "NoMovementAlert", text = "No Movement Alert", keywords = { "movement", "alert", "cooldown" } },
            { id = "PlayerAbsorbs", text = "Player Absorbs", keywords = { "absorb", "shield", "heal absorb", "necrotic", "pw:s", "power word shield", "damage absorb", "overlay" } },
            { id = "RaidNotifications", text = "Raid Notifications", keywords = { "raid", "notification", "alert", "gateway", "soulwell", "feast", "repair", "portal" } },
            { id = "ReadyCheckConsumables", text = "Ready Check Consumables", keywords = { "ready check", "consumable", "flask", "food", "rune", "potion", "missing" } },
            { id = "Recuperate",    text = "Recuperate Button", keywords = { "recuperate", "heal", "button" } },
            { id = "TimeSpiral",    text = "Time Spiral Tracker", keywords = { "time spiral", "evoker" } },
            { id = "WorldMarkerCycler", text = "World Marker Cycler", keywords = { "world marker", "marker", "raid marker", "cycle" } },
        },
    },
    {
        id = "healer_section",
        type = "header",
        text = "\226\128\162 Healer Utilities",
        defaultExpanded = false,
        items = {
            { id = "HealerTools", text = "Healer Tools", keywords = { "healer", "mana", "oom", "innervate", "maintenance", "buff", "uptime", "hot", "refresh", "tracker", "raid", "dungeon", "party", "druid", "cooldown", "duration", "count" } },
        },
    },
    {
        id = "qol_section",
        type = "header",
        text = "\226\128\162 Quality of Life",
        defaultExpanded = false,
        items = {
            { id = "Automation",        text = "Automation", keywords = { "automation", "auto", "role", "quest", "repair", "sell", "accept", "group", "duel", "delete", "ah", "auction house", "house", "housing", "vantus rune" } },
            { id = "CharacterPanel",    text = "Character Panel", keywords = { "character", "panel", "stats", "item level", "ilvl", "gear", "durability", "inspect" } },
            { id = "CombatLogger",      text = "Combat Logger", keywords = { "combat log", "logging", "advanced logging", "warcraftlogs", "raid" } },
            { id = "Nicknames",         text = "Custom Nicknames", keywords = { "nickname", "nicknames", "name", "custom", "rename" } },
            { id = "CVars",             text = "CVars", keywords = { "cvar", "cvars", "console", "variable", "setting", "world map", "map", "scale" } },
            { id = "GreatVaultAlert",   text = "Great Vault Alert", keywords = { "great vault", "vault", "weekly", "reward", "chest" } },
            { id = "DragonRiding",      text = "Skyriding UI", keywords = { "skyriding", "dragonriding", "dragon riding", "vigor", "speed", "fly" } },
            { id = "SlashCommands",     text = "Slash Commands", keywords = { "slash", "command", "commands", "slash command" } },
        },
    },
    {
        id = "skinning_section",
        type = "header",
        text = "\226\128\162 Skinning",
        defaultExpanded = false,
        elvUIDisabled = true,
        items = {
            { id = "SkinBlizzardFrames", text = "Blizzard Frames", keywords = { "blizzard", "frames", "chat config", "chat settings", "gm", "skin", "window", "dark theme", "dialog", "context menu", "right click", "font", "socket", "taxi", "flight", "guild invite", "addon skins", "widget", "widgets", "status bar", "progress", "power bar", "top center", "bar text" } },
            { id = "SkinMessages",     text = "Blizzard Texts", keywords = { "blizzard", "text", "message", "error", "raid warning", "ui error", "font", "fonts", "replace fonts", "quest text", "objective tracker", "mail" } },
            { id = "SkinTooltips",     text = "Blizzard Tooltips", keywords = { "tooltip", "tooltips", "blizzard", "mouseover", "skin", "anchor", "cursor", "spell id", "item id", "aura id", "guild rank", "mythic rating", "target", "health bar", "class color", "hide in combat" } },
            { id = "Chat",             text = "Chat", keywords = { "chat", "channel", "whisper", "tab", "timestamp", "copy", "guild", "message", "panel" } },
        },
    },
    {
        id = "dungeons_section",
        type = "header",
        text = "\226\128\162 Dungeon & Party Utilities",
        defaultExpanded = false,
        items = {
            { id = "DeathNotifications",          text = "Death Notifications", keywords = { "death", "notification", "died", "dead", "party", "m+", "mythic" } },
            { id = "DungeonCasts",                text = "Dungeon Casts", keywords = { "dungeon cast", "cast", "interrupt", "mob", "enemy", "castbar", "m+" } },
            { id = "EnemyCounter",                text = "Enemy Counter", keywords = { "enemy", "counter", "count", "mobs", "pull", "nameplate", "m+" } },
            { id = "FocusMarker",                 text = "Focus Marker", keywords = { "focus", "marker", "focus marker", "macro", "builder", "raid marker" } },
            { id = "GroupFinderPanel",            text = "Group Finder Panel", keywords = { "group finder", "lfg", "premade", "affix", "filter", "sort", "dungeon", "raider io", "m+" } },
            { id = "KickTracker",                 text = "Interrupt Tracker", keywords = { "interrupt", "kick", "tracker", "cc", "stop", "party", "m+" } },
            { id = "KeystoneHelper",              text = "Keystone Helper", keywords = { "keystone", "reset", "reroll", "key", "announcer", "mythic", "m+" } },
            { id = "LFGQuickCreate",              text = "LFG Quick Create", keywords = { "lfg", "group finder", "quick create", "premade", "list group", "keystone", "playstyle", "dungeon", "m+" } },
            { id = "LFGReminder",                 text = "LFG Reminder", keywords = { "lfg", "group finder", "teleport", "dungeon teleport", "reminder", "popup", "premade", "portal" } },
            { id = "MythicPlusTimer",             text = "Mythic+ Timer", keywords = { "mythic plus", "m+", "keystone", "timer", "forces", "deaths", "splits", "objective", "personal best", "affix", "warpdeplete" } },
            { id = "TargetedSpells",              text = "Targeted Spells", keywords = { "targeted", "spells", "cast", "incoming", "self", "target", "warning", "m+" } },
        },
    },
    {
        id = "dungeon_timers_section",
        type = "header",
        text = "\226\128\162 Dungeon Timers",
        defaultExpanded = false,
        disabledCheck = function()
            return not (KE.db and KE.db.profile and KE.db.profile.DungeonTimers
                and KE.db.profile.DungeonTimers.Enabled)
        end,
        items = {
            { id = "DTimers_General",                  text = "General",         alwaysEnabled = true, keywords = { "dungeon timers", "timer", "general", "bigwigs", "boss", "enable" } },
            { id = "DTimers_Bars",                     text = "Bar Settings", keywords = { "bar", "bars", "timer", "color", "texture", "size" } },
            { id = "DTimers_Texts",                    text = "Text Settings", keywords = { "text", "font", "label", "timer" } },
            { id = "DTimers_Nameplates",               text = "Nameplate Settings", alwaysEnabled = true, keywords = { "nameplate", "trash", "mob", "icon", "cooldown", "predict", "dungeon" } },
            { id = "DTimers_Dungeon_AlgetharAcademy",  text = "Algeth'ar Academy", keywords = { "algethar", "academy", "aa", "dungeon", "timer" } },
            { id = "DTimers_Dungeon_MagistersTerrace", text = "Magisters' Terrace", keywords = { "magisters", "terrace", "mgt", "dungeon", "timer" } },
            { id = "DTimers_Dungeon_MaisaraCaverns",   text = "Maisara Caverns", keywords = { "maisara", "caverns", "dungeon", "timer" } },
            { id = "DTimers_Dungeon_NexusPointXenas",  text = "Nexus-Point Xenas", keywords = { "nexus", "xenas", "nexus-point", "dungeon", "timer" } },
            { id = "DTimers_Dungeon_PitOfSaron",       text = "Pit of Saron", keywords = { "pit of saron", "saron", "pos", "dungeon", "timer" } },
            { id = "DTimers_Dungeon_SeatOfTriumvirate",text = "Seat of the Triumvirate", keywords = { "seat", "triumvirate", "sott", "dungeon", "timer" } },
            { id = "DTimers_Dungeon_Skyreach",         text = "Skyreach", keywords = { "skyreach", "dungeon", "timer" } },
            { id = "DTimers_Dungeon_WindrunnerSpire",  text = "Windrunner Spire", keywords = { "windrunner", "spire", "dungeon", "timer" } },
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
    frame:SetSize(950, 700)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(950, 550)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving(true) end)
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
    -- StartSizing is bound to OnDragStart, NOT OnMouseDown. WoW only fires
    -- OnDragStart after the cursor moves past the drag threshold, so a plain
    -- click no longer enters sizing mode. The previous OnMouseDown wiring
    -- caused rapid-click "spazzing": every click started a size operation,
    -- WoW's per-frame cursor polling registered 1-2px jitter as a delta, and
    -- each click contributed cumulative drift to the frame size.
    --
    -- Both OnDragStop and OnMouseUp call stopAndSaveResize because WoW
    -- suppresses OnMouseUp once the drag threshold has tripped (only
    -- OnDragStop fires for completed drags), but OnMouseUp is still needed
    -- for clicks that never reached drag threshold. The isResizing guard
    -- keeps the cleanup idempotent.
    local isResizing = false
    local function stopAndSaveResize()
        if not isResizing then return end
        isResizing = false
        frame:StopMovingOrSizing()
        -- StartSizing re-anchors to TOPLEFT internally; persist the new anchor
        -- alongside size so the next session restores a consistent layout.
        local point, _, relativePoint, xOfs, yOfs = frame:GetPoint()
        if KE.db and KE.db.global then
            local gs = KE.db.global.GUIState.frame
            gs.width = frame:GetWidth()
            gs.height = frame:GetHeight()
            gs.point = point
            gs.relativePoint = relativePoint
            gs.xOffset = xOfs
            gs.yOffset = yOfs
        end
    end
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnDragStart", function()
        if isResizing then return end
        isResizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnDragStop", stopAndSaveResize)
    resizeGrip:SetScript("OnMouseUp", stopAndSaveResize)
    resizeGrip:SetScript("OnHide", stopAndSaveResize)
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
