-- ╔══════════════════════════════════════════════════════════╗
-- ║  AddonTheme.lua                                          ║
-- ║  Purpose: Addon-wide theme system — 8 WoW-themed color   ║
-- ║           presets, class color mode, and custom colors.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local type = type
local pairs = pairs
local ipairs = ipairs
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local UnitClass = UnitClass
local pcall = pcall

---------------------------------------------------------------------------------
-- Theme Defaults
---------------------------------------------------------------------------------

local ThemeDefaults = {
    bgDark         = { 0.0627, 0.0627, 0.0627, 0.60 },
    bgMedium       = { 0.0902, 0.0902, 0.0902, 0.60 },
    bgLight        = { 0.0314, 0.0314, 0.0314, 0.60 },
    bgHover        = { 0.1804, 0.1804, 0.1804, 0.60 },
    border         = { 0, 0, 0, 1 },
    accent         = { 1.0, 0.0, 0.549, 1 },       -- #FF008C (KitnUI pink)
    accentHover    = { 1.0, 0.0, 0.549, 0.25 },
    accentDim      = { 0.80, 0.0, 0.439, 1 },
    textPrimary    = { 1, 1, 1, 1 },
    textSecondary  = { 1, 1, 1, 1 },
    textMuted      = { 1, 1, 1, 1 },
    selectedBg     = { 1.0, 0.0, 0.549, 0.20 },
    selectedText   = { 0.902, 0.902, 0.902, 1 },
    error          = { 0.90, 0.30, 0.30, 1 },
    success        = { 0.30, 0.80, 0.40, 1 },
    warning        = { 0.90, 0.75, 0.30, 1 },

    -- Dimensions
    headerHeight   = 32,
    footerHeight   = 24,
    sidebarWidth   = 200,
    contentWidth   = 540,
    borderSize     = 1,

    -- Spacing
    paddingSmall   = 4,
    paddingMedium  = 8,
    paddingLarge   = 12,
    scrollbarWidth = 14,

    -- Font settings
    fontFace       = "Fonts\\FRIZQT__.TTF",
    fontName       = "Expressway",
    fontSizeSmall  = 12,
    fontSizeNormal = 13,
    fontSizeLarge  = 16,
    fontOutline    = "OUTLINE",
    fontShadow     = false,
}
KE.ThemeDefaults = ThemeDefaults

---------------------------------------------------------------------------------
-- Theme Presets
---------------------------------------------------------------------------------
local function MakePreset(r, g, b)
    return {
        accent      = { r, g, b, 1 },
        accentHover = { r, g, b, 0.25 },
        accentDim   = { r * 0.8, g * 0.8, b * 0.8, 1 },
        selectedBg  = { r, g, b, 0.20 },
        selectedText = { 0.902, 0.902, 0.902, 1 },
    }
end

local THEME_PRESETS = {
    ["KitnUI"]      = MakePreset(1.0, 0.0, 0.549),       -- #FF008C Pink
    ["Nighthold"]   = MakePreset(0.451, 0.506, 1.0),      -- #7381FF Blue
    ["Firelands"]   = MakePreset(1.0, 0.42, 0.208),       -- #FF6B35 Orange
    ["Icecrown"]    = MakePreset(0.0, 0.749, 1.0),        -- #00BFFF Ice blue
    ["Dreamsurge"]  = MakePreset(0.125, 0.816, 0.043),     -- #20D00B Green
    ["Twilight"]    = MakePreset(0.608, 0.349, 0.714),     -- #9B59B6 Purple
    ["Sunwell"]     = MakePreset(1.0, 0.843, 0.0),        -- #FFD700 Gold
    ["Torghast"]    = MakePreset(0.627, 0.627, 0.627),     -- #A0A0A0 Gray
}

KE.ThemePresets = THEME_PRESETS
KE.ThemePresetOrder = { "KitnUI", "Nighthold", "Firelands", "Icecrown", "Dreamsurge", "Twilight", "Sunwell", "Torghast" }
KE.ThemeModeOptions = {
    { key = "preset", text = "Preset Theme" },
    { key = "class",  text = "Class Color" },
    { key = "custom", text = "Custom" },
}

local ACCENT_KEYS = { "accent", "accentHover", "accentDim", "selectedBg", "selectedText" }
local CLASS_COLOR_KEYS = { accent = true, accentHover = true, accentDim = true, selectedBg = true }

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function CopyColor(color)
    if type(color) ~= "table" then return { 1, 1, 1, 1 } end
    return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
end

local function GetPlayerClassRGB()
    local _, class = UnitClass("player")
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

---------------------------------------------------------------------------------
-- Theme Color Resolution
---------------------------------------------------------------------------------
function KE:GetThemeColor(key)
    local db = self.db and self.db.global and self.db.global.Theme
    if not db then return ThemeDefaults[key] end

    local mode = db.Mode or "preset"

    if mode == "preset" then
        local presetName = db.Preset or "KitnUI"
        local preset = THEME_PRESETS[presetName]
        if preset and preset[key] then
            return CopyColor(preset[key])
        end
    elseif mode == "class" then
        if CLASS_COLOR_KEYS[key] then
            local r, g, b = GetPlayerClassRGB()
            if key == "accent" then
                return { r, g, b, 1 }
            elseif key == "accentHover" then
                return { r, g, b, 0.25 }
            elseif key == "accentDim" then
                return { r * 0.8, g * 0.8, b * 0.8, 1 }
            elseif key == "selectedBg" then
                return { r, g, b, 0.20 }
            end
        end
    elseif mode == "custom" then
        local custom = db.Custom
        if custom and custom[key] then
            return CopyColor(custom[key])
        end
    end

    return ThemeDefaults[key] and CopyColor(ThemeDefaults[key]) or nil
end

---------------------------------------------------------------------------------
-- Live Theme Table
---------------------------------------------------------------------------------
KE.Theme = {}
for k, v in pairs(ThemeDefaults) do
    if type(v) == "table" then KE.Theme[k] = CopyColor(v) else KE.Theme[k] = v end
end

---------------------------------------------------------------------------------
-- Refresh Theme
---------------------------------------------------------------------------------
local isRefreshing = false
function KE:RefreshTheme()
    if isRefreshing then return end
    isRefreshing = true
    local T = self.Theme

    -- Copy all base values from ThemeDefaults
    for k, v in pairs(ThemeDefaults) do
        if type(v) == "table" then T[k] = CopyColor(v) else T[k] = v end
    end

    -- Override accent-family colors from current mode (if DB is available)
    if self.db and self.db.global and self.db.global.Theme then
        for _, key in ipairs(ACCENT_KEYS) do
            local resolved = self:GetThemeColor(key)
            if resolved then T[key] = resolved end
        end
    end

    -- Propagate to GUI and EditMode
    if self.GUIFrame and self.GUIFrame.mainFrame and self.GUIFrame.mainFrame:IsShown() then
        self.GUIFrame:ApplyThemeColors()
    end
    if self.EditMode and self.EditMode:IsActive() then
        self.EditMode:RefreshOverlays()
    end
    self:NotifyThemeChange()
    isRefreshing = false
end

---------------------------------------------------------------------------------
-- Theme Setters
---------------------------------------------------------------------------------
function KE:SetThemeMode(mode)
    if not self.db or not self.db.global then return end
    self.db.global.Theme.Mode = mode
    self:RefreshTheme()
end

function KE:SetThemePreset(presetName)
    if not self.db or not self.db.global then return end
    if not THEME_PRESETS[presetName] then return end
    self.db.global.Theme.Preset = presetName
    self:RefreshTheme()
end

function KE:SetCustomColor(key, r, g, b, a)
    if not self.db or not self.db.global then return end
    local custom = self.db.global.Theme.Custom
    if not custom then
        self.db.global.Theme.Custom = {}
        custom = self.db.global.Theme.Custom
    end
    custom[key] = { r, g, b, a or 1 }
    self:RefreshTheme()
end

function KE:CopyPresetToCustom()
    if not self.db or not self.db.global then return end
    local presetName = self.db.global.Theme.Preset or "KitnUI"
    local preset = THEME_PRESETS[presetName]
    if not preset then return end
    local custom = self.db.global.Theme.Custom
    if not custom then
        self.db.global.Theme.Custom = {}
        custom = self.db.global.Theme.Custom
    end
    for _, key in ipairs(ACCENT_KEYS) do
        if preset[key] then
            custom[key] = CopyColor(preset[key])
        end
    end
end

function KE:ResetTheme()
    if not self.db or not self.db.global then return end
    self.db.global.Theme = {
        Mode = "preset",
        Preset = "KitnUI",
        Custom = {},
    }
    self:RefreshTheme()
end

---------------------------------------------------------------------------------
-- Theme Change Notification
---------------------------------------------------------------------------------
function KE:NotifyThemeChange()
    if not KitnEssentials then return end
    for _, module in KitnEssentials:IterateModules() do
        if module.OnThemeChanged then
            pcall(module.OnThemeChanged, module)
        end
    end
end

---------------------------------------------------------------------------------
-- Font Helper
---------------------------------------------------------------------------------
function KE:ApplyThemeFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local T = self.Theme
    local fs
    if type(size) == "number" then
        fs = size
    elseif size == "small" then
        fs = T.fontSizeSmall or 11
    elseif size == "large" then
        fs = T.fontSizeLarge or 14
    else
        fs = T.fontSizeNormal or 12
    end
    local fo = T.fontOutline or "OUTLINE"
    local ff = T.fontFace or "Fonts\\FRIZQT__.TTF"
    if fo == "NONE" then fo = "" end
    fontString:SetFont(ff, fs, fo)
    if T.fontShadow then
        fontString:SetShadowOffset(1, -1)
        fontString:SetShadowColor(0, 0, 0, 0.8)
    else
        fontString:SetShadowOffset(0, 0)
        fontString:SetShadowColor(0, 0, 0, 0)
    end
end
