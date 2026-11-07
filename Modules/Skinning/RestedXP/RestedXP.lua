-- ╔══════════════════════════════════════════════════════════╗
-- ║  RestedXP.lua                                            ║
-- ║  Module: RestedXP                                        ║
-- ║  Purpose: RestedXP Guides in KitnEssentials' look: the   ║
-- ║           theme, the arrow, the step icons and one guide ║
-- ║           window.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SkinRestedXP: AceModule
local M = KitnEssentials:NewModule("SkinRestedXP")

-- OnDisable gives everything back, so a profile switch can turn it off live.
M.keLiveSkin = true

local C_AddOns = C_AddOns
local pairs, pcall, type = pairs, pcall, type

local Safe, Rules, Theme = KE.RestedXPSafe, KE.RestedXPRules, KE.RestedXPTheme
local Arrow, Icons, Setup, Window = KE.RestedXPArrow, KE.RestedXPIcons, KE.RestedXPSetup, KE.RestedXPWindow

local RXP_ADDON = "RXPGuides"
local PART_SITES = {
    Theme = "theme calls",
    Arrow = "arrow frame",
    Icons = "icons table",
    Setup = "saved profile",
    Window = "guide window calls",
}
local TEXT_ICONS_BACK = "RestedXP's own step icons come back after a reload."
local TEXT_ICONS_COLOR = "RestedXP's step icons take the new color after a reload."

function M:UpdateDB()
    self.db = KE.db.profile.SkinRestedXP
    Setup.ProfileChanged()
end

-- RestedXP builds rows from its icons as a guide loads, and reads Beta, V2 and its
-- theme as it starts, so the icons, the theme and setup's writes go in then.
-- RestedXP calls this global after it makes its settings database and before it
-- imports themes, loads guides or builds a window; it sets one global and creates
-- nothing. With the module off it runs only for a waiting Undo.
local function PrepareEarly(self, enabled)
    if C_AddOns.IsAddOnLoaded(RXP_ADDON) then
        -- RestedXP has started: a late icon swap shows an icon twice, and setup's
        -- start-up writes cannot run. Setup keeps this load's start-up facts.
        Setup.Due(true)
        return
    end
    local earlier = _G.RXPOnInitialize
    Setup.Due(false)
    _G.RXPOnInitialize = function()
        _G.RXPOnInitialize = earlier
        if type(earlier) == "function" then pcall(earlier) end
        Safe.Run("SetupBoot", Setup.Boot)
        if enabled then
            Safe.Run("IconsApply", Icons.Apply)
            Safe.Run("ThemeAddEarly", Theme.AddEarly)
        end
    end
end

-- Off with nothing waiting, this step is two field reads and two calls that
-- return at once. The one stated exception to the module shape: it creates no
-- frame, event or hook.
function M:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
    local waiting = Setup.TakePending()
    local enabled = self.db.Enabled and KE:IsFeatureAvailable("SkinRestedXP") and not KE:ShouldNotLoadModule()
    if not (enabled or waiting) then return end
    -- This load's question, asked with no character: the GUID LoadsNext needs is
    -- not shown to exist yet at this point.
    if C_AddOns.GetAddOnEnableState(RXP_ADDON) == 0 then return end
    self.atLogin = enabled or nil
    PrepareEarly(self, enabled)
end

local function WindowWanted(self)
    if not self.parts.Window then return false end
    local v2 = _G.RXP.v2
    local v2On = Safe.Run("WindowGate", v2.IsGuideWindowEnabled, v2) and true or false
    local rival = KE:RestedXPRivalSettings()
    return Rules.WindowMayStart(v2On, rival ~= nil and rival.rxpWindow == true)
end

local function StartParts(self)
    local wasRunning = Window.IsActive()
    if self.parts.Theme then Theme.Register() end
    if self.parts.Arrow and Theme.Option("ArrowEnabled") then
        Arrow.Start()
    else
        Arrow.Stop()
    end
    if WindowWanted(self) then
        Window.Start()
    else
        Window.Stop()
    end
    -- This Character's line reads the window.
    if Window.IsActive() ~= wasRunning then Setup.ProfileChanged() end
end

function M:OnEnable()
    local atLogin = self.atLogin
    self.atLogin = nil
    if not self.db.Enabled then return end
    if not (C_AddOns.IsAddOnLoaded(RXP_ADDON) and type(_G.RXP) == "table") then return end
    self.parts = Rules.Parts(_G.RXP)
    for part, on in pairs(self.parts) do
        if not on then Safe.Missing(part, PART_SITES[part]) end
    end
    if atLogin and Setup.StartMissed() then
        self.parts.Icons = false
        Safe.Missing("Icons", "start-up call")
    end
    -- Turning the module on in a session writes nothing to RestedXP: a new
    -- character's setup runs only at a start that found it on.
    if self.parts.Setup then Setup.AtStart(atLogin) end
    StartParts(self)
end

-- Called on every PLAYER_ENTERING_WORLD for an enabled module, so Show In needs
-- no zone event of its own.
function M:ApplySettings()
    if not (self:IsEnabled() and self.parts) then return end
    StartParts(self)
    Window.ApplySettings()
end

-- KE's window tints its icons from their path, so only RestedXP's own window can
-- show the accent an icon started with.
local function AskIfIconsStale()
    if not Window.IsActive() and Icons.AccentStale() then KE:CreateReloadPrompt(TEXT_ICONS_COLOR) end
end

function M:ThemeChanged()
    if not (self:IsEnabled() and self.parts) then return end
    local asked = false
    if self.parts.Theme then asked = Theme.Refresh() end
    Arrow.Paint()
    Window.Recolor()
    if not asked then AskIfIconsStale() end
end

function M:OnThemeChanged()
    self:ThemeChanged()
end

function M:AskIconsBack()
    if Icons.Applied() then KE:CreateReloadPrompt(TEXT_ICONS_BACK) end
end

-- Writes nothing to RestedXP and leaves the setup record alone.
function M:ResetToDefaults()
    local db = self.db
    local enabled, newCharacters = db.Enabled, db.SetUpNewCharacters
    wipe(db)
    for key, value in pairs(KE:GetDefaultDB().profile.SkinRestedXP) do
        db[key] = type(value) == "table" and CopyTable(value) or value
    end
    db.Enabled, db.SetUpNewCharacters = enabled, newCharacters
    self:ThemeChanged()
    self:ApplySettings()
end

function M:OnDisable()
    Window.Stop()
    Arrow.Stop()
    Setup.RestoreTheme()
end
