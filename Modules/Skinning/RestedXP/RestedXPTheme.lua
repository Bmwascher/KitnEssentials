-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPTheme.lua             ║
-- ║  Purpose: The KitnEssentials theme in RestedXP and its   ║
-- ║           reload.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local type = type

local Safe, Rules = KE.RestedXPSafe, KE.RestedXPRules
local Has, Dig, Run = Safe.Has, Safe.Dig, Safe.Run

local Theme = {}
KE.RestedXPTheme = Theme

local TEXT_LIVE_OFF = "RestedXP's live theme reload is off, so this takes a reload."

local lastBuilt, reloadPending, askedLate

local function DB()
    return KE.db.profile.SkinRestedXP
end

function Theme.Option(key)
    return Rules.Option(key, DB()[key])
end

function Theme.Tokens()
    return Rules.Tokens(KE.Theme.accent)
end

function Theme.WindowColors()
    local db = DB()
    return Rules.WindowColors(Theme.Tokens(), Theme.Option("Panel") and db.PanelColor or nil,
        Theme.Option("BoxOpacity"), Theme.Option("WindowColors"), {
            title = db.ColorTitle, text = db.ColorText, line = db.ColorLine, box = db.ColorBox,
            border = db.ColorBorder, barFill = db.ColorBarFill, barBack = db.ColorBarBack,
        })
end

-- At RestedXP's start a media pack loaded after it has not named its fonts yet, so
-- that build uses the path kept from a load that found the global font.
local function FontPath(early)
    local name, lsm = KE:GetGlobalFont(), KE.LSM
    local found = lsm and name and lsm:Fetch("font", name, true) or nil
    local store = KE:GetCharStore(false)
    local kept = store and store.RestedXPFont
    local path, keep = Rules.ThemeFont(name, found, kept, early == true, KE:GetFontPath())
    if keep ~= kept then KE:GetCharStore(true).RestedXPFont = keep end
    return path
end

function Theme.Build(early)
    return Rules.ThemeFields(Theme.Tokens(), FontPath(early), DB().PanelColor)
end

local function Profile()
    local profile = Dig(_G.RXP, "settings", "profile")
    return type(profile) == "table" and profile or nil
end

local function SavedIsOurs()
    local profile = Profile()
    return profile ~= nil and profile.activeTheme == Rules.THEME_NAME
end

local function ActiveIsOurs()
    return Dig(_G.RXP, "activeTheme", "name") == Rules.THEME_NAME
end

---------------------------------------------------------------------------------
-- Registering and reloading
---------------------------------------------------------------------------------
-- ReloadTheme touches the secure Targets and Items frames with no combat guard,
-- so one reload waits for combat to end, however many changes ask for it.
function Theme.Reload()
    if reloadPending then return end
    reloadPending = true
    KE:RunAfterCombat(function()
        reloadPending = false
        local rxp = _G.RXP
        if Has(rxp, "ReloadTheme") then Run("ReloadTheme", rxp.ReloadTheme, rxp) end
    end)
end

function Theme.LiveReloadOff()
    local profile = Profile()
    return profile ~= nil and not profile.enableThemeLiveReload
end

-- ReloadTheme does nothing with RestedXP's live reload off, so the saved theme
-- then waits for a UI reload. True when it asked for one.
function Theme.ReloadOrAsk()
    if Theme.LiveReloadOff() then
        KE:CreateReloadPrompt(TEXT_LIVE_OFF)
        return true
    end
    Theme.Reload()
    return false
end

-- RestedXP reads this list as it starts, before guides load.
function Theme.AddEarly()
    local list = _G.RXPGuides_Themes
    if type(list) ~= "table" then
        list = {}
        _G.RXPGuides_Themes = list
    end
    list[Rules.THEME_NAME] = Theme.Build(true)
    lastBuilt = Theme.Build(true)
end

-- Sends the theme only if its values changed, and says so. A reload re-renders all
-- of RestedXP's frames, and KE reports every theme and profile change, including
-- those that change nothing here. RestedXP fills in the table it is given, so the
-- kept one is a separate copy.
local function Send()
    local built = Theme.Build()
    if Rules.SameDeep(built, lastBuilt) then return false end
    local rxp = _G.RXP
    if not Has(rxp, "RegisterTheme") then return false end
    lastBuilt = built
    Run("RegisterTheme", rxp.RegisterTheme, rxp, Theme.Build())
    return true
end

-- This runs at every loading screen, so a declined reload is asked for only once.
function Theme.Register()
    local changed = Send()
    if not SavedIsOurs() or (ActiveIsOurs() and not changed) then return end
    if Theme.LiveReloadOff() and askedLate then return end
    askedLate = true
    Theme.ReloadOrAsk()
end

-- A change KE reports. True when it asked for a reload.
function Theme.Refresh()
    if not (Send() and SavedIsOurs()) then return false end
    return Theme.ReloadOrAsk()
end
