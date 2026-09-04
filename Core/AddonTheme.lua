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
    -- Depth comes from opacity stacking inside one near-black family, not from
    -- stepping the grey. Card bodies read marginally lighter than the window,
    -- which is deliberate: the alternative reads as a hole in the panel.
    bgDark         = { 0.031, 0.031, 0.031, 0.80 }, -- #080808 window / content pane / inputs
    bgMedium       = { 0.055, 0.055, 0.055, 0.95 }, -- #0E0E0E sidebar / title bar / footer / controls
    bgLight        = { 0.055, 0.055, 0.055, 0.80 }, -- #0E0E0E card bodies / sliders / dialogs
    bgHover        = { 0.227, 0.227, 0.227, 0.80 }, -- #3A3A3A hover
    border         = { 0, 0, 0, 1 },
    accent         = { 1.0, 0.0, 0.549, 1 },       -- #FF008C (KitnUI pink)
    accentHover    = { 1.0, 0.0, 0.549, 0.25 },
    accentDim      = { 0.80, 0.0, 0.439, 1 },
    textPrimary    = { 1, 1, 1, 1 },
    textSecondary  = { 1, 1, 1, 1 },
    textMuted      = { 1, 1, 1, 1 },
    selectedBg     = { 1.0, 0.0, 0.549, 0.35 },
    selectedText   = { 0.902, 0.902, 0.902, 1 },
    error          = { 0.90, 0.30, 0.30, 1 },
    success        = { 0.30, 0.80, 0.40, 1 },
    warning        = { 0.90, 0.75, 0.30, 1 },

    -- Dimensions
    headerHeight   = 32,
    footerHeight   = 24,
    sidebarWidth   = 200,
    contentWidth   = 679,
    borderSize     = 1,

    -- Row heights (used by the settings cards: FontSettingsCard, GlowSettingsCard, etc.)
    rowHeight          = 40,   -- Standard row height
    rowHeightLast      = 44,   -- Last row in a card (use 0 spacing in AddRow)
    rowHeightTall      = 80,   -- Anchor point selector rows
    rowHeightSeparator = 8,    -- Separator-only rows
    rowHeightNote      = 50,   -- "Note" text block at the foot of a card

    -- Spacing
    paddingSmall   = 4,
    paddingMedium  = 8,
    paddingLarge   = 16,
    scrollbarWidth = 14,
    animDuration   = 0.18, -- Standard hover animation duration

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
        selectedBg  = { r, g, b, 0.35 },
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

-- The colour skinned Blizzard frames take when the accent is not allowed to
-- reach them: visible against the near-black windows, not a brand colour.
local SKIN_NEUTRAL = { 0.651, 0.651, 0.651, 1 }
KE.SkinNeutralColor = SKIN_NEUTRAL
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

local function ColorsMatch(a, b)
    if not a or not b then return a == b end
    for i = 1, 3 do
        if a[i] ~= b[i] then return false end
    end
    return true
end
KE.ColorsMatch = ColorsMatch

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

-- The colour the skinning palette receives. The settings window always follows
-- the accent; skinned Blizzard frames follow it only while TintSkins is on.
-- Absent or nil TintSkins means on, so a profile written before the switch
-- existed keeps behaving exactly as it did.
function KE:GetSkinBrandColor()
    local db = self.db and self.db.global and self.db.global.Theme
    if db and db.TintSkins == false then
        return CopyColor(SKIN_NEUTRAL)
    end
    return self:GetThemeColor("accent")
end

---------------------------------------------------------------------------------
-- Live Theme Table
---------------------------------------------------------------------------------
KE.Theme = {} --[[@as KETheme]]
for k, v in pairs(ThemeDefaults) do
    if type(v) == "table" then KE.Theme[k] = CopyColor(v) else KE.Theme[k] = v end
end

---------------------------------------------------------------------------------
-- Refresh Theme
---------------------------------------------------------------------------------
local isRefreshing = false
-- Theme version counter — incremented on every successful RefreshTheme.
-- Pool consumers cache the version their kits were last refreshed at and
-- re-apply theme colors lazily inside their Configure path when the
-- counter has advanced. Avoids per-render theme-apply cost on hot paths
-- (e.g. DungeonTimers timer-clicks) while still updating cached pool
-- kits when the user actually switches themes. See `card:ApplyThemeColors`
-- in GUI-Core and `:ApplyThemeColors` on KESlider/KEDropdown/KEEditBox/KEToggle.
KE._themeVersion = 0

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

    -- Bump version BEFORE GUI propagation so RefreshContent's pool Configures
    -- can pick up the new value during the synchronous re-render below.
    KE._themeVersion = (KE._themeVersion or 0) + 1

    -- Propagate to GUI and EditMode
    if self.GUIFrame and self.GUIFrame.mainFrame and self.GUIFrame.mainFrame:IsShown() then
        self.GUIFrame:ApplyThemeColors()
    end
    if self.EditMode and self.EditMode:IsActive() then
        self.EditMode:RefreshOverlays()
    end
    -- The skinning palette takes its accent from the theme, and it is NOT a
    -- module, so NotifyThemeChange below cannot reach it. It has to be
    -- refreshed here or not at all: its own file-scope call runs before the db
    -- exists, and its only other call site sits inside the Blizzard Frames
    -- module, which ships disabled -- so a user's saved accent never reached
    -- any skin consumer on a default profile, and a live theme change never
    -- reached one at all. Ordered BEFORE the notification so a future skinning
    -- OnThemeChanged handler observes the new palette rather than the old.
    if self.Skins and self.Skins.RefreshPalette then
        self.Skins.RefreshPalette()
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

-- Skinned regions take their colour once, at frame-build time, so flipping this
-- switch only reaches frames built after it. The palette is updated immediately
-- regardless, so anything built later is already correct.
function KE:SetTintSkins(enabled)
    if not self.db or not self.db.global or not self.db.global.Theme then return end
    local before = self:GetSkinBrandColor()
    self.db.global.Theme.TintSkins = enabled and true or false
    local after = self:GetSkinBrandColor()
    self:RefreshTheme()
    if not KE.ColorsMatch(before, after) then
        self:FlagReloadNeeded()
    end
end

function KE:ResetTheme()
    if not self.db or not self.db.global then return end
    local wasTintOff = (self.db.global.Theme.TintSkins == false)
    local before = self:GetSkinBrandColor()
    self.db.global.Theme = {
        Mode = "preset",
        Preset = "KitnUI",
        Custom = {},
        TintSkins = true,
    }
    self:RefreshTheme()
    local after = self:GetSkinBrandColor()
    if wasTintOff and not KE.ColorsMatch(before, after) then
        self:FlagReloadNeeded()
    end
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
