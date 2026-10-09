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
local abs, floor = math.abs, math.floor

---------------------------------------------------------------------------------
-- Sidebar Data
---------------------------------------------------------------------------------

-- Search matches the whole query as ONE literal substring of the title or of
-- a single keyword, so a row hosting tabs spells out each tab label and every
-- keyword of each page it absorbed, as a phrase, apostrophe variants included.
GUIFrame.sidebarConfig = {
    {
        id = "settings_section",
        type = "header",
        text = "\226\128\162 Core",
        defaultExpanded = true,
        items = {
            { id = "HomePage", text = "Home Page", keywords = { "home", "home page", "start", "welcome", "overview", "about", "changelog", "theme", "color", "accent", "appearance", "skin", "preset", "tint" } },
            { id = "Profiles", text = "Profile Manager", keywords = { "profile", "profiles", "import", "export", "copy", "reset", "rename", "delete", "global", "sharing" } },
            { id = "CVars", text = "CVars", keywords = { "cvar", "cvars", "console", "variable", "setting", "world map", "world map scale", "map", "map scale", "scale", "maximized", "maximised", "fullscreen", "maximized map", "ui scaling", "core panels", "services", "housing", "legacy / optional", "legacy", "panel scale", "panel scaling", "blizzard panels", "character frame", "professions scale", "group finder scale", "housing scale", "service panels", "legacy panels" } },
            { id = "Optimize", text = "System Optimization", keywords = { "optimize", "performance", "fps", "cpu", "memory", "latency", "cvar" } },
        },
    },
    {
        id = "combat_section",
        type = "header",
        text = "\226\128\162 Combat",
        defaultExpanded = false,
        items = {
            { id = "ClassTools",    text = "Class Tools", keywords = { "class", "class tools", "tools", "all classes", "evoker", "dragon", "empower", "disintegrate", "disintegrate ticks", "ticks", "augmentation", "devastation", "preservation", "stasis", "havoc", "havoc tracker", "havoc warning", "havoc target", "target has havoc", "warlock", "destruction", "destro", "destruction warlock", "warlock havoc", "hunter", "hunters mark", "hunter's mark", "hunter: mark missing", "mark", "marksman", "beast mastery", "survival", "stance", "stance text", "form", "forms", "missing forms", "shapeshift", "druid", "warrior", "paladin", "priest", "presence", "aura", "utilities", "general", "priest: pi macro", "pi macro", "priest: pi assist", "pi assist", "power infusion", "power infusion assist", "pi", "assist", "burst", "glow", "raid frame", "macro", "builder", "trinket", "racial", "recuperate", "heal", "button", "time spiral", "tracker", "dot tracker", "dot", "dots", "multidot", "mage", "alter time", "shaman", "nature's guardian", "natures guardian", "thunderous paws", "ghost wolf" } },
            { id = "CombatRes",     text = "Combat Res", keywords = { "battle res", "brez", "combat res", "resurrect", "raid res", "cr" } },
            { id = "CombatTexts",   text = "Combat Texts", keywords = { "combat text", "scrolling", "no target", "interrupt", "durability" } },
            { id = "CombatTimer",   text = "Combat Timer", keywords = { "combat timer", "encounter", "duration", "stopwatch", "fight length" } },
            { id = "Cursor",        text = "Cursor Effects", keywords = { "cursor", "mouse", "pointer", "trail", "circle", "dispel", "cleanse", "purge", "magic", "curse", "poison", "disease", "debuff", "taunt", "flame shock", "garrote", "provoke", "growl", "torment", "dark command", "hand of reckoning" } },
            { id = "FocusCastbar",  text = "Focus Castbar", keywords = { "castbar", "cast", "focus", "casting", "interrupt" } },
            { id = "CombatCross",   text = "Player Crosshair", keywords = { "crosshair", "cross", "aim", "reticle", "player", "always show", "out of combat", "shape", "circle", "hide in range" } },
            { id = "RangeChecker",  text = "Range Display", keywords = { "range", "distance", "yards", "melee", "ranged" } },
            { id = "StatusTexts",   text = "Status Texts", keywords = { "status", "status texts", "texts", "combat potion", "potion", "pot", "consumable", "healer", "healer mana", "mana", "oom", "raid", "dungeon", "party", "movement", "no movement alert", "movement alert", "alert", "cooldown", "pet", "pet status", "pet status texts", "hunter", "warlock", "demon", "summon", "absorb", "player absorbs", "shield", "heal absorb", "necrotic", "pw:s", "power word shield", "damage absorb", "overlay" } },
        },
    },
    {
        id = "aura_section",
        type = "header",
        text = "\226\128\162 Aura Tracking",
        defaultExpanded = false,
        items = {
            { id = "AuraHeaders_Buffs",   text = "Player Buffs", keywords = { "buff", "buffs", "player buffs", "aura", "auras", "weapon enchant", "enchant", "blizzard", "replace" } },
            { id = "AuraHeaders_Debuffs", text = "Player Debuffs", keywords = { "debuff", "debuffs", "player debuffs", "aura", "auras", "magic", "curse", "poison", "disease", "blizzard", "replace" } },
            { id = "AuraDebuffs",   text = "Advanced Debuffs", keywords = { "debuff", "debuffs", "aura", "boss", "dot", "magic", "curse", "poison", "disease" } },
            { id = "AuraExternals", text = "External Tracker", keywords = { "external", "externals", "defensive", "buff", "cooldown", "mitigation" } },
            { id = "PartyBuffs",    text = "Party Buffs", keywords = { "party", "party buffs", "buff", "buffs", "external", "defensive", "burst", "potion", "trinket", "cooldown", "arena" } },
            { id = "AuraMovement", text = "Movement Buffs", keywords = { "movement", "speed", "sprint", "buff", "mobility" } },
            { id = "TotemTracker",  text = "Totem Tracker", keywords = { "totem", "totems", "shaman", "evoker" } },
        },
    },
    {
        id = "qol_section",
        type = "header",
        text = "\226\128\162 QoL",
        defaultExpanded = false,
        items = {
            { id = "Automation",        text = "Automation", keywords = { "automation", "auto", "role", "quest", "repair", "sell", "accept", "group", "duel", "delete", "ah", "auction house", "house", "housing", "vantus rune", "merchant", "vendor", "pages", "shop", "buy", "buyback", "extend", "wide", "combat logger", "combat log", "logging", "advanced logging", "warcraftlogs", "raid", "scenario", "scenarios", "delve", "delves", "torghast", "warcraft recorder", "recorder", "preset" } },
            { id = "BonusRoll",         text = "Bonus Roll", keywords = { "bonus roll", "bonus", "coin", "roll", "pass", "auto pass", "auto-pass", "loot spec", "confirm", "seal" } },
            { id = "GroupTools",        text = "Group Tools", keywords = { "group", "raid tools", "utilities", "general", "raid", "raid notifications", "notification", "notifications", "alert", "gateway", "soulwell", "feast", "repair", "portal", "ready check", "consumables", "flask", "food", "rune", "missing", "world marker", "world markers", "marker", "raid marker", "cycle", "cycler" } },
            { id = "QualityOfLife",     text = "Quality of Life", keywords = { "quality of life", "qol", "spell alert opacity", "spell alert", "opacity", "proc", "alert", "glow", "overlay", "great vault alert", "great vault", "vault", "weekly", "reward", "chest", "copy anything", "copy", "spell id", "item id", "npc id", "aura id", "macro", "clipboard", "tooltip", "move frames", "move", "mover", "drag", "draggable", "reposition", "position", "window", "windows", "frame", "frames", "blizzard", "panel", "unlock", "slash", "slash command", "command", "commands", "shortcut", "reload" } },
            { id = "SecondaryStats",    text = "Secondary Stats Display", keywords = { "secondary stats", "stats", "stat", "crit", "critical strike", "haste", "mastery", "versatility", "vers", "leech", "lifesteal", "avoidance", "speed", "rating", "percent", "readout", "display" } },
        },
    },
    {
        id = "dungeons_section",
        type = "header",
        text = "\226\128\162 Dungeon Tools",
        defaultExpanded = false,
        items = {
            { id = "KeystoneHelper",              text = "Keystone Helper", keywords = { "keystone", "reset", "instance reset", "reroll", "key", "announcer", "mythic", "m+", "group finder", "lfg", "premade", "affix", "filter", "sort", "dungeon", "raider io", "quick create", "list group", "playstyle", "teleport", "dungeon teleport", "reminder", "popup", "portal" } },
            { id = "DungeonAlerts",               text = "Dungeon Alerts", keywords = { "death notifications", "death", "notification", "died", "dead", "party", "m+", "mythic", "enemy counter", "enemy", "counter", "count", "mobs", "pull", "nameplate", "targeted spells", "targeted", "spells", "cast", "incoming", "self", "target", "warning" } },
            { id = "DTimers_Main", text = "Dungeon Timers", keywords = { "dungeon timers", "timer", "timers", "bigwigs", "boss", "season", "enable", "general", "bar", "bars", "color", "texture", "size", "text", "font", "label", "nameplate", "trash", "mob", "icon", "cooldown", "predict", "dungeon", "algethar", "aa", "mgt", "pos", "sott" } },
            { id = "KicksCasts",                  text = "Kicks & Casts", keywords = { "focus", "marker", "focus marker", "focus macros", "macro", "builder", "raid marker", "kick", "interrupt", "focus kick", "interrupt tracker", "tracker", "cc", "stop", "party", "m+", "dungeon casts", "dungeon cast", "cast", "mob", "enemy", "castbar", "cc tracker", "crowd control", "polymorph", "ring of frost", "hex", "repentance", "turn evil", "freezing trap", "scare beast", "sap", "blind", "banish", "fear", "seduction", "mesmerize", "hibernate", "entangling roots", "imprison", "sleep walk", "paralysis", "shackle horror" } },
        },
    },
    {
        id = "skinning_section",
        type = "header",
        text = "\226\128\162 Skinning",
        defaultExpanded = false,
        elvUIDisabled = true,
        items = {
            -- Dark Theme leads rather than sorting alphabetically: it is the
            -- section's master page and hosts most of the section's pages
            -- behind its own tab strip, either as a top-level tab, chained
            -- onto General, or nested inside the Elements sub-row.
            --
            -- An item without alwaysEnabled is grayed and unclickable under
            -- ElvUI. Dark Theme's General tab carries Color Picker and Raid
            -- Control, neither of which has an ElvUI gate of its own; Character
            -- Panel, Damage Meter, Mythic+ Timer and Skyriding UI are not skins.
            -- Chat and Tooltips do stand down, and stay clickable so their page
            -- can say so.
            --
            -- The keyword list absorbs the rows this page swallowed, so
            -- searching "raid control", "ilvl", "hex" or "objective tracker"
            -- still lands here.
            { id = "SkinBlizzardFrames", text = "Dark Theme", alwaysEnabled = true, keywords = { "blizzard", "frames", "chat config", "chat settings", "gm", "skin", "window", "dark theme", "dialog", "context menu", "right click", "font", "socket", "taxi", "flight", "guild invite", "addon skins", "widget", "widgets", "status bar", "progress", "power bar", "top center", "bar text", "alert", "alerts", "toast", "toasts", "loot", "achievement", "banner", "recipe", "level up", "anchor", "move", "position",
                "character", "panel", "stats", "item level", "ilvl", "gear", "durability", "inspect",
                "color", "colour", "picker", "rgb", "hex", "alpha", "opacity", "swatch", "class color",
                "raid", "control", "raid control", "ready check", "readycheck", "countdown", "pull", "timer", "marker", "markers", "world marker", "raid marker", "difficulty", "assist", "everyone assist", "role", "roles", "tank", "healer", "raid manager", "raid tools", "shared notes", "group",
                "text", "message", "error", "raid warning", "ui error", "fonts", "replace fonts", "quest text", "objective tracker", "mail",
                "vehicle", "vehicle exit", "vehicle exit button", "exit", "leave", "eject", "dismount", "button",
                "frame skins", "loot roll", "loot window", "ui widgets", "alert frames",
                "skinned windows", "blizzard text everywhere", "category sizes",
                "on-screen messages", "error messages", "action status", "zone names", "zone text", "chat bubbles",
                "status bars", "text widgets", "spell icons", "top-center container", "top-center position",
                "alert stack position", "event toasts", "event toast position", } },
            { id = "CharacterPanel",     text = "Character Panel", alwaysEnabled = true, keywords = { "character", "panel", "character panel", "character screen", "stats", "item level", "ilvl", "gear", "durability", "inspect", "gems", "sockets", "enchant", "great vault", "vault", "omnium", "window buttons" } },
            { id = "Chat",               text = "Chat", alwaysEnabled = true, keywords = { "chat", "channel", "whisper", "tab", "timestamp", "copy", "guild", "message", "panel" } },
            { id = "DamageMeter",        text = "Damage Meter", keywords = { "damage meter", "dps", "damage", "healing", "threat", "meter", "recount", "details" }, alwaysEnabled = true },
            { id = "MythicPlusTimer",    text = "Mythic+ Timer", keywords = { "mythic plus", "m+", "keystone", "timer", "forces", "deaths", "splits", "objective", "personal best", "affix", "warpdeplete" }, alwaysEnabled = true },
            { id = "DragonRiding",       text = "Skyriding UI", alwaysEnabled = true, keywords = { "skyriding", "dragonriding", "dragon riding", "vigor", "speed", "fly" } },
            { id = "SkinTooltips",       text = "Tooltips", alwaysEnabled = true, keywords = { "tooltip", "tooltips", "blizzard", "mouseover", "skin", "anchor", "cursor", "spell id", "item id", "aura id", "guild rank", "mythic rating", "target", "health bar", "class color", "hide in combat" } },
        },
    },
}

-- Searching a dungeon by name must still surface the Dungeon Timers page
-- now that the per-dungeon sidebar items are gone. Names come from the
-- registry so a future season lands in search with no edit here.
for _, section in ipairs(GUIFrame.sidebarConfig) do
    if section.id == "dungeons_section" then
        for _, item in ipairs(section.items) do
            if item.id == "DTimers_Main" then
                for _, d in ipairs(KE.DungeonTimerDungeons or {}) do
                    item.keywords[#item.keywords + 1] = d.name:lower()
                end
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Content Area
---------------------------------------------------------------------------------
function GUIFrame:CreateContentArea(parent)
    local T = Theme

    -- Three points fully constrain the frame, so the pane absorbs every resize
    -- delta while the sidebar keeps its fixed width. The left edge offsets from
    -- the frame rather than anchoring to the sidebar, which does not exist yet:
    -- CreateSidebar runs after this function.
    local content = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    content:SetPoint("TOPLEFT", parent, "TOPLEFT", T.borderSize + T.sidebarWidth, -(T.headerHeight + T.borderSize))
    content:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -T.borderSize, -(T.headerHeight + T.borderSize))
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -T.borderSize, T.borderSize)

    content:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    -- The window paints one fill for the whole body. A second fill here would
    -- stack with it and drive the result toward opaque.
    content:SetBackdropColor(0, 0, 0, 0)

    -- Derived arithmetically rather than read off the frame: an anchor-only
    -- frame can still measure 1x1 before its first layout pass, and the content
    -- builders below must never see a zero-width parent.
    local function ResolveContentWidth()
        local frameWidth = parent:GetWidth()
        if not frameWidth or frameWidth <= 1 then
            frameWidth = T.sidebarWidth + T.contentWidth + (T.borderSize * 2)
        end
        return frameWidth - T.sidebarWidth - (T.borderSize * 2)
    end

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
    scrollChild:SetWidth(ResolveContentWidth())
    scrollFrame:SetScrollChild(scrollChild)

    -- Scrollbar visibility
    local scrollbarVisible = false
    local function UpdateScrollChildWidth()
        local width = ResolveContentWidth()
        if scrollbarVisible then
            width = width - scrollbarWidth
        end
        scrollChild:SetWidth(width)
    end

    local function UpdateScrollBarVisibility()
        if scrollFrame.ScrollBar then
            local contentH = scrollChild:GetHeight()
            local frameH = scrollFrame:GetHeight()
            local needsScrollbar = contentH > frameH
            local flipped = needsScrollbar ~= scrollbarVisible
            scrollbarVisible = needsScrollbar
            scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
            UpdateScrollChildWidth()
            -- The bar's width came or went, so card notes may wrap differently.
            -- A minimized window cannot change width (the grip is hidden), so
            -- a flip from collapsing it is undone by the restore.
            if flipped and not GUIFrame.minimized then GUIFrame:QueueLabelRecheck() end
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
    -- Kept on the table because ToggleMinimize has to drop the height minimum
    -- to collapse and put it back to restore, and two copies of these numbers
    -- would drift.
    GUIFrame.minWidth, GUIFrame.minHeight = 950, 550
    frame:SetResizeBounds(GUIFrame.minWidth, GUIFrame.minHeight)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    -- Resize/move instrumentation. The runaway enlarge is intermittent, so the
    -- log has to be armed before it happens rather than switched on after.
    -- The flag hangs off the FRAME because that is what has a global name --
    -- the addon table is private to the file scope and unreachable from /run:
    --   /run KE_GUIFrame.DEBUG_RESIZE = true
    -- Every handler on both the move path and the size path reports, so the
    -- ORDER they fire in is visible -- a move and a size both engaging is the
    -- shape worth ruling in or out, and it cannot be seen from the end state.
    GUIFrame.isResizing = false
    local function resizeLog(tag)
        if not frame.DEBUG_RESIZE then return end
        local point, _, relativePoint, xOfs, yOfs = frame:GetPoint()
        KE:Print(string.format("%s w=%.1f h=%.1f %s>%s %.1f,%.1f sizing=%s",
            tag, frame:GetWidth() or -1, frame:GetHeight() or -1,
            tostring(point), tostring(relativePoint),
            xOfs or 0, yOfs or 0, tostring(GUIFrame.isResizing)))
    end

    frame:SetScript("OnSizeChanged", function() resizeLog("size") end)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        resizeLog("moveStart")
        f:StartMoving(true)
    end)
    frame:SetScript("OnDragStop", function(f)
        resizeLog("moveStop")
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

    -- Minimize button: collapses the window to its title bar so in-world
    -- elements can be adjusted without closing the page you are working on.
    -- Sits next to close because both are window-state controls.
    local minimizeBtn = CreateFrame("Button", nil, header)
    minimizeBtn:SetSize(18, 18)
    minimizeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    local minimizeIcon = minimizeBtn:CreateTexture(nil, "ARTWORK")
    minimizeIcon:SetAllPoints()
    minimizeIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png")
    minimizeIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    minimizeIcon:SetTexelSnappingBias(0)
    minimizeIcon:SetSnapToPixelGrid(true)

    -- The arrow points at what the click does: down to collapse, up to
    -- restore. Unrotated the texture already points down.
    local function PaintMinimizeArrow()
        minimizeIcon:SetRotation(GUIFrame.minimized and math.pi or 0)
    end
    PaintMinimizeArrow()
    GUIFrame.PaintMinimizeArrow = PaintMinimizeArrow

    minimizeBtn:SetScript("OnEnter", function(self)
        minimizeIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GUIFrame.minimized and "Expand" or "Minimize")
        GameTooltip:Show()
    end)
    minimizeBtn:SetScript("OnLeave", function(self)
        minimizeIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        if not GameTooltip:IsForbidden() and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    minimizeBtn:SetScript("OnClick", function()
        GUIFrame:ToggleMinimize()
    end)
    GUIFrame.minimizeBtn = minimizeBtn

    -- Toggle Anchors button
    local editModeBtn = CreateFrame("Button", nil, header)
    editModeBtn:SetSize(18, 18)
    editModeBtn:SetPoint("RIGHT", minimizeBtn, "LEFT", -8, 0)
    local editModeIcon = editModeBtn:CreateTexture(nil, "ARTWORK")
    editModeIcon:SetAllPoints()
    editModeIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomMove.png")
    editModeIcon:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    editModeIcon:SetTexelSnappingBias(0)
    editModeIcon:SetSnapToPixelGrid(true)
    editModeBtn.icon = editModeIcon

    -- Exposed so EditMode's Enter/Exit and theme changes can repaint it.
    local editModeHovered = false
    local function PaintEditModeButton()
        local lit = editModeHovered or (KE.EditMode and KE.EditMode:IsActive())
        local c = lit and T.accent or T.textSecondary
        editModeIcon:SetVertexColor(c[1], c[2], c[3], 1)
    end
    GUIFrame.PaintEditModeButton = PaintEditModeButton

    editModeBtn:SetScript("OnEnter", function(self)
        editModeHovered = true
        PaintEditModeButton()
        if GameTooltip:IsForbidden() then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Toggle Anchors")
        GameTooltip:Show()
    end)
    editModeBtn:SetScript("OnLeave", function(self)
        editModeHovered = false
        PaintEditModeButton()
        if not GameTooltip:IsForbidden() and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
    editModeBtn:SetScript("OnClick", function()
        if KE.EditMode then
            KE.EditMode:Toggle()
        end
    end)
    GUIFrame.editModeBtn = editModeBtn

    -- Home button (custom texture)
    local homeBtn = CreateFrame("Button", nil, header)
    homeBtn:SetSize(18, 18)
    homeBtn:SetPoint("RIGHT", editModeBtn, "LEFT", -8, 0)
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
        GUIFrame:DropQueuedPage()
        GUIFrame:SelectSidebarItem("HomePage")
    end)

    -- Header bottom border
    local headerBorder = header:CreateTexture(nil, "BORDER")
    headerBorder:SetHeight(T.borderSize)
    headerBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Close on ESC (popup first, then clear search if focused, then the window)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            if GUIFrame.themePopupShown then
                GUIFrame:HideThemePopup()
            elseif GUIFrame.searchEditBox and GUIFrame.searchEditBox:HasFocus() then
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

    -- One reload prompt per GUI session, raised on the way out. Hooked on the
    -- FRAME rather than GUIFrame:Hide so no close path can skip it -- the
    -- Escape key, the combat auto-close and the profile switcher all reach
    -- here. Set BEFORE the Hide() below, which is inert because only a user
    -- action ever sets the flag.
    frame:SetScript("OnHide", function()
        if KE.FlushPendingReloadPrompt then KE:FlushPendingReloadPrompt() end
    end)

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
    bottomBar:SetBackdropColor(0, 0, 0, 0)
    -- Held on the frame so ToggleMinimize can hide it with the rest of the body.
    GUIFrame.bottomBar = bottomBar

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
    versionText:SetText("|cff888888v" .. (KE.Version or "?") .. "|r")
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
    local sizeAtGrab
    local function stopAndSaveResize()
        resizeLog("sizeStop")
        if not GUIFrame.isResizing then return end
        GUIFrame.isResizing = false
        frame:StopMovingOrSizing()

        -- A click that never became a drag must not commit a size. WoW polls
        -- the cursor every frame while sizing, so even a still hand registers a
        -- pixel or two, and each stray click used to bank that drift for good.
        if sizeAtGrab then
            local w, h = frame:GetWidth(), frame:GetHeight()
            if abs(w - sizeAtGrab[1]) < 2 and abs(h - sizeAtGrab[2]) < 2 then
                frame:SetSize(sizeAtGrab[1], sizeAtGrab[2])
            end
            sizeAtGrab = nil
        end

        -- Whole pixels only. StartSizing leaves fractions behind, they persist
        -- into SavedVariables, and they compound across sessions.
        frame:SetSize(floor(frame:GetWidth() + 0.5), floor(frame:GetHeight() + 0.5))
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
        GUIFrame:ResetLabelRebuilds()
        GUIFrame:QueueLabelRecheck()
    end
    -- Sizing starts on the PRESS, while the cursor is provably still on the
    -- grip. StartSizing snaps the dragged corner to wherever the cursor is when
    -- it runs, so any gap between the two becomes an instant jump -- and
    -- OnDragStart, by definition, only fires once the cursor has already left.
    -- That was the runaway enlarge: one discontinuity at the first size event,
    -- then a perfectly smooth drag.
    --
    -- RegisterForDrag stays. The whole window is draggable, so without it the
    -- press would bubble up and start MOVING the window mid-resize. OnDragStart
    -- still fires afterward and the isResizing guard makes it a no-op.
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or GUIFrame.isResizing then return end
        resizeLog("sizeStart")
        GUIFrame.isResizing = true
        sizeAtGrab = { frame:GetWidth(), frame:GetHeight() }
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnDragStart", function()
        if GUIFrame.isResizing then return end
        GUIFrame.isResizing = true
        sizeAtGrab = { frame:GetWidth(), frame:GetHeight() }
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
        -- A Show still waiting a frame for its build counts as open.
        local pending = GUIFrame._openPending
        GUIFrame._openPending = nil
        if GUIFrame:IsShown() then
            GUIFrame.reopenAfterCombat = true
            GUIFrame:Hide()
        elseif pending then
            GUIFrame.reopenAfterCombat = true
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if GUIFrame.reopenAfterCombat then
            GUIFrame.reopenAfterCombat = nil
            GUIFrame:Show()
        end
    end
end)
