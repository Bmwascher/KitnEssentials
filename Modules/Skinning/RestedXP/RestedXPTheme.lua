-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPTheme.lua             ║
-- ║  Purpose: The KitnEssentials theme in RestedXP, its      ║
-- ║           reload, and the repaint of RestedXP's own      ║
-- ║           window chrome.                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local hooksecurefunc = hooksecurefunc
local ipairs, type, unpack = ipairs, type, unpack

local Safe, Rules = KE.RestedXPSafe, KE.RestedXPRules
local Has, Dig, Run = Safe.Has, Safe.Dig, Safe.Run

local Theme = {}
KE.RestedXPTheme = Theme

local GRIP = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\grip.tga"
local BARS = { "GuideName", "Footer" }
local ARROWS = { "ScrollUpButton", "ScrollDownButton" }
local ARROW_PARTS = { "Normal", "Highlight", "Pushed", "Disabled" }
local THUMB_W, THUMB_H = 8, 40
local RULE_DROP, RULE_H = 3, 1
local SHOWN_PARTS = { {}, { "GuideName" }, { "Footer" }, { "ScrollChild" }, { "ScrollFrame", "ScrollBar" } }
local TEXT_LIVE_OFF = "RestedXP's live theme reload is off, so this takes a reload."

local lastBuilt, reloadPending, askedLate, chromeOn, chromeHooked
local footerTinted, scrollTinted, gripOriginal, thumbSize, ruleColor, ruleRows
local faded = setmetatable({}, { __mode = "k" })
local rules = setmetatable({}, { __mode = "k" })

local function DB()
    return KE.db.profile.SkinRestedXP
end

function Theme.Option(key)
    return Rules.Option(key, DB()[key])
end

function Theme.Tokens()
    local preset = DB().AccentPreset and KE.ThemePresets[DB().AccentPreset]
    return Rules.Tokens(Theme.Option("Palette"), preset and preset.accent or KE.Theme.accent)
end

function Theme.WindowColors()
    local db = DB()
    return Rules.WindowColors(Theme.Tokens(), Theme.Option("FollowPalette"),
        Theme.Option("Panel") and db.PanelColor or nil, Theme.Option("BoxOpacity"), Theme.Option("WindowColors"), {
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
    return Rules.ThemeFields(Theme.Tokens(), Theme.Option("FollowPalette"), FontPath(early), DB().PanelColor)
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

---------------------------------------------------------------------------------
-- Chrome on RestedXP's own windows
---------------------------------------------------------------------------------
local function ChromeColor()
    if not (chromeOn and ActiveIsOurs()) then return nil end
    local color = Dig(_G.RXP, "activeTheme", "chromeColor")
    return type(color) == "table" and color or nil
end

local function DividerColor()
    if not (chromeOn and ActiveIsOurs()) then return nil end
    local color = Dig(_G.RXP, "activeTheme", "dividerColor")
    return type(color) == "table" and color or nil
end

local function Visible(region)
    return region ~= nil and region:IsVisible()
end

local function Banner(name)
    local banner = Dig(_G.RXPFrame, name, "bg")
    return type(banner) == "table" and banner or nil
end

-- Each part paints only while visible, because under V2 RestedXP leaves parts
-- behind. It gives back whether visible or not, so turning off leaves nothing.
local function PaintBars()
    local hide = chromeOn and ActiveIsOurs()
    for _, name in ipairs(BARS) do
        local banner = Banner(name)
        if Has(banner, "SetAlpha") then
            if hide and Visible(banner) then
                banner:SetAlpha(0)
                faded[banner] = true
            elseif not hide and faded[banner] then
                banner:SetAlpha(1)
                faded[banner] = nil
            end
        end
    end
end

local function Skin(texture, path, color)
    if not Has(texture, "SetVertexColor") then return end
    if path and Has(texture, "SetTexture") then texture:SetTexture(path) end
    local r, g, b, a = 1, 1, 1, 1
    if color then r, g, b, a = color[1], color[2], color[3], color[4] or 1 end
    texture:SetVertexColor(r, g, b, a)
end

local function Normal(button)
    return Has(button, "GetNormalTexture") and button:GetNormalTexture() or nil
end

-- SetColorTexture replaces the thumb's image, and RestedXP's UpdateScrollBar is
-- what sets it back. Without that call the thumb stays as it is.
local function PaintThumb(thumb, color)
    local frame = _G.RXPFrame
    if not (Has(thumb, "SetSize") and Has(thumb, "GetSize") and Has(frame, "UpdateScrollBar")) then return end
    thumbSize = thumbSize or { thumb:GetSize() }
    if color and Has(thumb, "SetColorTexture") then
        thumb:SetColorTexture(color[1], color[2], color[3], color[4])
        thumb:SetSize(THUMB_W, THUMB_H)
    else
        Run("ChromeScrollBar", frame.UpdateScrollBar)
        thumb:SetSize(thumbSize[1], thumbSize[2])
    end
end

local function PaintFooter(color)
    local frame = _G.RXPFrame
    local grip = Normal(Dig(frame, "Footer", "icon"))
    if Has(grip, "GetTexture") then gripOriginal = gripOriginal or grip:GetTexture() end
    Skin(Normal(Dig(frame, "Footer", "cog")), nil, color)
    Skin(grip, color and GRIP or gripOriginal, color)
end

local function PaintScrollBar(color)
    local bar = Dig(_G.RXPFrame, "ScrollFrame", "ScrollBar")
    PaintThumb(Has(bar, "GetThumbTexture") and bar:GetThumbTexture() or nil, color)
    for _, name in ipairs(ARROWS) do
        for _, part in ipairs(ARROW_PARTS) do
            local texture = Dig(bar, name, part)
            if Has(texture, "SetAlpha") then texture:SetAlpha(color and 0 or 1) end
        end
    end
end

local function PaintChrome()
    local color = ChromeColor()
    local frame = _G.RXPFrame
    if color and Visible(Dig(frame, "Footer")) then
        footerTinted = true
        PaintFooter(color)
    elseif footerTinted and not color then
        footerTinted = false
        PaintFooter(nil)
    end
    if color and Visible(Dig(frame, "ScrollFrame", "ScrollBar")) then
        scrollTinted = true
        PaintScrollBar(color)
    elseif scrollTinted and not color then
        scrollTinted = false
        PaintScrollBar(nil)
    end
end

local function PaintRules()
    local list = Dig(_G.RXPFrame, "ScrollChild", "framePool")
    local color = DividerColor()
    if type(list) ~= "table" then
        ruleColor = color
        return
    end
    if color and not Visible(Dig(_G.RXPFrame, "ScrollChild")) then return end
    if color == ruleColor and #list == ruleRows then return end
    for _, row in ipairs(list) do
        local rule = rules[row]
        if color and not rule and Has(row, "CreateTexture") then
            rule = row:CreateTexture(nil, "ARTWORK")
            rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -RULE_DROP)
            rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -RULE_DROP)
            rule:SetHeight(RULE_H)
            rules[row] = rule
        end
        if rule and color then
            rule:SetColorTexture(color[1], color[2], color[3], color[4])
            rule:Show()
        elseif rule then
            rule:Hide()
        end
    end
    ruleColor, ruleRows = color, #list
end

local function PaintLegacy()
    PaintBars()
    PaintChrome()
    PaintRules()
end

local function PaintIfWanted()
    if chromeOn or footerTinted or scrollTinted or ruleColor then PaintLegacy() end
end

local function HookChrome()
    if chromeHooked then return end
    chromeHooked = true
    local frame = _G.RXPFrame
    for _, name in ipairs(BARS) do
        local banner = Banner(name)
        if Has(banner, "SetTexture") then hooksecurefunc(banner, "SetTexture", PaintIfWanted) end
    end
    if Has(frame, "UpdateScrollBar") then hooksecurefunc(frame, "UpdateScrollBar", PaintIfWanted) end
    if Has(_G.RXP, "SetStep") then hooksecurefunc(_G.RXP, "SetStep", PaintIfWanted) end
    for _, path in ipairs(SHOWN_PARTS) do
        local part = #path > 0 and Dig(frame, unpack(path)) or frame
        if Has(part, "HookScript") then part:HookScript("OnShow", PaintIfWanted) end
    end
end

function Theme.Start(wantChrome)
    Theme.Register()
    chromeOn = wantChrome == true
    if chromeOn then HookChrome() end
    if chromeHooked then PaintLegacy() end
end

function Theme.Stop()
    chromeOn = false
    if chromeHooked then PaintLegacy() end
end
