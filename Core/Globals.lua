-- ╔══════════════════════════════════════════════════════════╗
-- ║  Globals.lua                                             ║
-- ║  Purpose: Global constants, helper functions, preview    ║
-- ║           manager, and edit mode integration.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
---@diagnostic disable: undefined-field
local KE = select(2, ...)
local addonName = select(1, ...)

local ipairs = ipairs
local print = print
local string_gsub = string.gsub
local ReloadUI = ReloadUI
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local EditModeManagerFrame = EditModeManagerFrame
local _G = _G

---------------------------------------------------------------------------------
-- Libraries and Media
---------------------------------------------------------------------------------

KE.LSM = LibStub("LibSharedMedia-3.0")
---@type LibDualSpec-1.0?
KE.LDS = LibStub("LibDualSpec-1.0", true)

KE.PATH = ([[Interface\AddOns\%s\Media\]]):format(addonName)
KE.FONT = KE.PATH .. [[Fonts\]] .. "Expressway.TTF"

-- Gem socket types, ordered as the socket-helper scan walks them. Shared
-- because two unrelated features need the same list: CharacterPanel's socket
-- helper and the Character window skin's empty-socket icons. `locale` is the
-- Blizzard global whose string a tooltip line is matched against; `icon` is
-- the fallback fileID when the socket is empty.
KE.GEM_SOCKET_TYPES = {
    { name = "Prismatic",  locale = "EMPTY_SOCKET_PRISMATIC",  icon = 458977 },
    { name = "Meta",       locale = "EMPTY_SOCKET_META",       icon = 136257 },
    { name = "Tinker",     locale = "EMPTY_SOCKET_TINKER",     icon = 2958630 },
    { name = "Cogwheel",   locale = "EMPTY_SOCKET_COGWHEEL",   icon = 407324 },
    { name = "Primordial", locale = "EMPTY_SOCKET_PRIMORDIAL", icon = 4095404 },
    { name = "Fiber",      locale = "EMPTY_SOCKET_FIBER",      icon = 136260 },
}

-- Role icons for group-finder and role-check displays. Keyed by the string
-- Blizzard's role APIs return, so a lookup miss is the correct no-op.
KE.ROLE_ICONS = {
    TANK    = KE.PATH .. [[RoleIcons\tank-modern.png]],
    HEALER  = KE.PATH .. [[RoleIcons\healer-modern.png]],
    DAMAGER = KE.PATH .. [[RoleIcons\dps-modern.png]],
}

if KE.LSM then
    KE.LSM:Register("font", "Expressway", KE.FONT)
    KE.LSM:Register("statusbar", "KitnUI", KE.PATH .. [[Statusbars\KitnEssentials.blp]])
    -- "Details! Slash": Details' bar_of_bars.png, shipped here as DetailsSlash.png under the
    -- SAME LSM name Details uses, so a profile referencing it keeps the texture even with
    -- Details disabled/uninstalled (LSM keeps the first registration of a name). .png loads in 12.0.
    KE.LSM:Register("statusbar", "Details! Slash", KE.PATH .. [[Statusbars\DetailsSlash.png]])
    KE.LSM:Register("border", "WHITE8X8", [[Interface\Buttons\WHITE8X8]])

    -- KitnEssentials sound presets — surfaced in every LSM-aware sound
    -- dropdown (Sound settings cards, DungeonTimers per-spell sound picker,
    -- etc.) alongside Blizzard's built-ins and the user's other LSM addons.
    -- Names match the .ogg filename so the dropdown label is the source of
    -- truth — keep the table in sync if files are added/renamed/removed.
    local SOUND_DIR = KE.PATH .. [[Sounds\]]
    local sounds = {
        "Add", "Adds", "AoE", "Aoe And Dance",
        "Boss Buffed", "CC", "Clear", "Dance", "Defensive",
        "Dispell", "Dmg Amp", "Dodge", "Drop", "Feet",
        "Fixate Incoming", "Frontal", "Gun1", "Hide",
        "Intermission", "Interrupt", "Kick", "Knockback", "Leap",
        "Move", "Phasing", "Pools", "Pull", "Soak", "Soaks", "Split",
        "Spread", "Stack", "Stop Casting", "Totem",
    }
    for _, name in ipairs(sounds) do
        KE.LSM:Register("sound", name, SOUND_DIR .. name .. ".ogg")
    end
end

---------------------------------------------------------------------------------
-- Media Helpers
---------------------------------------------------------------------------------

-- The profile-wide font. Every module and skin that has not been given a font
-- of its own resolves here, so one setting moves the whole addon.
---@return string fontName
function KE:GetGlobalFont()
    local profile = self.db and self.db.profile
    return (profile and profile.GlobalFont) or "Expressway"
end

-- A nil fontName means "no per-module choice", which resolves to the global
-- font. Every font application reaches this, so no module needs to read the
-- setting itself.
function KE:GetFontPath(fontName)
    fontName = fontName or self:GetGlobalFont()
    if KE.LSM and fontName then
        local path = KE.LSM:Fetch("font", fontName)
        if path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- Returns the LSM font NAME a module is configured with, never a file path --
-- wrap it in KE:GetFontPath when a path is wanted. Modules disagree on the key
-- (FontFace / Font / fontFace), which is the only reason this is a helper.
-- Hoisted from an inline copy in Tooltips.lua so the skin modules share one
-- definition; two copies of a resolution rule drifting apart is a failure mode
-- this project has already had.
---@param moduleDB table? Module settings table
---@return string fontName
function KE:GetEffectiveFont(moduleDB)
    return moduleDB and (moduleDB.FontFace or moduleDB.Font or moduleDB.fontFace) or "Friz Quadrata TT"
end

function KE:GetStatusbarPath(barName)
    if KE.LSM and barName then
        local path = KE.LSM:Fetch("statusbar", barName)
        if path then return path end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

---------------------------------------------------------------------------------
-- Addon Metadata
---------------------------------------------------------------------------------

local function GetAddonMetadata()
    if not C_AddOns then return end
    KE.AddOnName = C_AddOns.GetAddOnMetadata(addonName, "Title")
    local ver = C_AddOns.GetAddOnMetadata(addonName, "Version")
    if not ver or ver:find("@") then
        ver = C_AddOns.GetAddOnMetadata(addonName, "X-Manual-Version") or "dev"
    end
    KE.Version = ver:gsub("^v", "")
    KE.Author = C_AddOns.GetAddOnMetadata(addonName, "Author")
end
GetAddonMetadata()

---------------------------------------------------------------------------------
-- Utility Helpers
---------------------------------------------------------------------------------

-- Returns true when ElvUI is active and user wants ElvUI to handle skinning
function KE:ShouldNotLoadModule()
    return C_AddOns.IsAddOnLoaded("ElvUI") and self.db and self.db.profile.UseElvUI and self.db.profile.UseElvUI.Enabled
end

function KE:IsEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

function KE:Print(msg)
    print(self:ColorTextByTheme("Kitn") .. "Essentials:|r " .. msg)
end

-- Run fn now, or defer it to the next PLAYER_REGEN_ENABLED when in combat
-- lockdown. Queued closures run once, FIFO, each via xpcall(fn,
-- geterrorhandler()) so one erroring closure cannot drop the rest of the
-- queue. Secure-frame mutations (state drivers, secure attributes,
-- Show/Hide on protected frames) route through this instead of executing
-- blocked mid-combat.
function KE:RunAfterCombat(fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    if not self._combatQueue then
        self._combatQueue = {}
        self._combatQueueFrame = CreateFrame("Frame")
        self._combatQueueFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        self._combatQueueFrame:SetScript("OnEvent", function()
            local fns = KE._combatQueue
            KE._combatQueue = {}
            for i = 1, #fns do xpcall(fns[i], geterrorhandler()) end
        end)
    end
    self._combatQueue[#self._combatQueue + 1] = fn
end

-- Recommend disabling a redundant external addon when a KitnEssentials
-- replacement module is enabled alongside it. Prints ONCE (the flag re-arms if
-- the addon is later removed, so it warns again only if the addon returns). The
-- once-flag lives on the caller-supplied table at `key` (pass the module's db).
-- Deferred a few seconds so it lands after the login chat settles.
function KE:WarnRedundantAddon(addon, label, moduleName, slash, state, key)
    if not (state and C_AddOns and C_AddOns.IsAddOnLoaded) then return end
    if not C_AddOns.IsAddOnLoaded(addon) then
        state[key] = nil   -- re-arm: addon gone, warn again only if it returns
        return
    end
    if state[key] then return end
    C_Timer.After(5, function()
        -- Flag inside the callback: a /reload during the defer window must not
        -- mark the warning delivered (SavedVariables persist instantly; the print
        -- doesn't). Re-check the addon — it can disappear during the defer.
        if state[key] then return end
        if not C_AddOns.IsAddOnLoaded(addon) then return end
        state[key] = true
        KE:Print(label .. " is enabled alongside the KitnEssentials " .. moduleName
            .. " - you only need one. Disable " .. label .. ", or turn off the "
            .. moduleName .. " in |cffffff00" .. slash .. "|r.")
    end)
end

---------------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------------

SLASH_KITNESSENTIALS1 = "/kes"
SLASH_KITNESSENTIALS2 = "/kitnessentials"
SLASH_KITNESSENTIALS3 = "/dunnigan"
SlashCmdList["KITNESSENTIALS"] = function(msg)
    msg = msg or ""
    msg = string_gsub(msg, "^%s+", "")
    msg = string_gsub(msg, "%s+$", "")

    -- /kes profiler <...> routes to the profiler with case preserved
    -- (snapshot labels are case-sensitive). Match before the lowercase pass.
    local profileRest = msg:match("^[Pp][Rr][Oo][Ff][Ii][Ll][Ee][Rr]%s*(.*)$")
                     or msg:match("^[Pp][Rr][Oo][Ff]%s*(.*)$")
    if profileRest then
        if KE.Profiler and KE.Profiler.RunCommand then
            KE.Profiler.RunCommand(profileRest)
        else
            KE:Print("profiler not loaded.")
        end
        return
    end

    -- /kes dm <...> routes the rest to the Damage Meter module's slash handler
    -- ("reset" clears sessions; anything else toggles the dock). The module mixes
    -- HandleSlash on DM; nil-guarded so a disabled/unbuilt module is a no-op.
    local dmRest = msg:match("^[Dd][Mm]%s*(.*)$")
    if dmRest then
        local dm = KitnEssentials and KitnEssentials:GetModule("DamageMeter", true)
        if dm and dm.HandleSlash then
            dm:HandleSlash(dmRest)
        end
        return
    end

    -- /kes mt opens the Mythic+ Timer GUI page (matches /kes dm's module route).
    -- HandleSlash-first dispatch: the module gains a HandleSlash in a later
    -- phase for demo/preview subcommands; until then the GUI fallback runs.
    local mtRest = msg:match("^[Mm][Tt]%s*(.*)$")
    if mtRest ~= nil then
        local mt = KitnEssentials and KitnEssentials:GetModule("MythicPlusTimer", true)
        if mt and mt.HandleSlash then
            mt:HandleSlash(mtRest)
        elseif KE.GUIFrame and KE.GUIFrame.OpenPage then
            -- OpenPage(itemId, sectionId, context) self-shows the GUI, expands
            -- the section, and selects the page.
            KE.GUIFrame:OpenPage("MythicPlusTimer", "skinning_section")
        end
        return
    end

    -- /kes skins [verify|rerun <key> [selector]] — skin dispatch diagnostics.
    -- Matched before the lowercase pass because rerun takes a skin key and
    -- the keys are CamelCase.
    local skinRest = msg:match("^[Ss][Kk][Ii][Nn][Ss]%s*(.*)$")
    if skinRest then
        local S = KE.Skins
        if not S then
            KE:Print("skinning not loaded.")
            return
        end
        local rerunKey, rerunSelector = skinRest:match("^[Rr][Ee][Rr][Uu][Nn]%s+(%S+)%s*(%S*)$")
        if rerunKey then
            if rerunSelector == "" then rerunSelector = nil end
            if S.DebugRerun then S.DebugRerun(rerunKey, rerunSelector) end
        elseif skinRest == "" or skinRest:lower() == "verify" then
            if S.DebugVerify then S.DebugVerify() end
        else
            KE:Print("usage: /kes skins verify | /kes skins rerun <key> [selector]")
        end
        return
    end

    msg = msg:lower()
    if msg == "" or msg == "gui" then
        if KE.GUIFrame then
            KE.GUIFrame:Toggle()
        end
    elseif msg == "edit" or msg == "unlock" then
        if KE.EditMode then
            KE.EditMode:Toggle()
        end
    elseif msg == "wa" or msg == "wa on" or msg == "wa off" then
        -- The handler lives in the SlashCommands module, which is where the
        -- registration it flips lives too.
        if KE.HandleWACommand then
            KE:HandleWACommand(msg:match("^wa%s*(%a*)$"))
        else
            KE:Print("slash commands are not loaded.")
        end
    elseif msg == "resetgui" then
        if KE.db and KE.db.global then
            KE.db.global.GUIState = nil
            KE.db.global._guiReset = true
        end
        ReloadUI()
    elseif msg == "trash" then
        -- Diagnostic snapshot of the Dungeon Trash tracker (see DTrash:DumpState).
        local dt = KitnEssentials and KitnEssentials:GetModule("DungeonTrash", true)
        if dt and dt.DumpState then
            dt:DumpState()
        else
            KE:Print("Dungeon Trash tracker unavailable.")
        end
    elseif msg == "conflicts" then
        -- Re-runs the addon conflict scan (Core/Conflicts.lua) so a resolved
        -- conflict can be retested without a relog. Silent when nothing
        -- conflicts. Nil-guarded like the module routes above.
        if KE.ScanAddonConflicts then
            KE:ScanAddonConflicts()
        end
    else
        -- "help" and anything unrecognized: list every subcommand.
        KE:Print("Commands: /kes or gui (settings) | edit or unlock | wa [on|off] | profiler or prof | dm [reset | report [count] [channel]] | mt [clearsplits] | skins [verify | rerun <key>] | trash | conflicts | resetgui")
    end
end

---------------------------------------------------------------------------------
-- Initialization Message
---------------------------------------------------------------------------------

function KE:Init()
    C_Timer.After(2, function()
        if KE.db and KE.db.global and KE.db.global._guiReset then
            KE.db.global._guiReset = nil
            KE:Print("GUI Reset")
        elseif KE.db and KE.db.profile.ShowChatMessage then
            KE:Print(KE:ColorTextByTheme("/kes") .. " to open the configuration window.")
        end
    end)
end

---------------------------------------------------------------------------------
-- Frame Positioning
---------------------------------------------------------------------------------

function KE:ResolveAnchorFrame(anchorFrameType, parentFrameName)
    if anchorFrameType == "SCREEN" or anchorFrameType == "UIPARENT" then
        return UIParent
    elseif anchorFrameType == "PLAYERFRAME" then
        -- Auto-detect the active unit-frame addon's player frame.
        return _G.ElvUF_Player or _G.UUF_Player
            or _G.EllesmereUIUnitFrames_Player or _G.PlayerFrame or UIParent
    elseif anchorFrameType == "SELECTFRAME" and parentFrameName then
        local frame = _G[parentFrameName]
        return frame or UIParent
    end
    return UIParent
end

---------------------------------------------------------------------------------
-- Font Helpers
---------------------------------------------------------------------------------

-- SOFTOUTLINE named a custom 8-shadow renderer that no longer exists. The
-- option is still offered and still sits in saved profiles, so it resolves to
-- a plain outline here rather than being rejected: a stored value keeps
-- working and only the look changes.
function KE:GetFontOutline(outline)
    if outline == "SOFTOUTLINE" then return "OUTLINE" end
    if not outline or outline == "NONE" or outline == "" then
        return ""
    end
    return outline
end

-- Single source of truth for the font-outline dropdown option list used by
-- every GUI font card. The base set (None/Outline/Thick) is always returned.
-- Slug is now a profile-wide switch (KE:SlugFlags) rather than a per-module
-- mode, so it no longer appears here. Pass flags for the two optional modes
-- that aren't universally appropriate:
--   includeSoft  → SOFTOUTLINE   (KE's 8-shadow custom outline; pulls in
--                                 extra FontStrings, can misbehave on
--                                 recycled tiny-text Blizzard frames)
--   includeMono  → MONOCHROME    (no anti-aliasing; specialized, e.g.
--                                 nameplate text)
-- Adding a new mode here picks it up everywhere automatically.
function KE:GetFontOutlineOptions(flags)
    flags = flags or {}
    local opts = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
    }
    if flags.includeSoft then
        opts[#opts + 1] = { key = "SOFTOUTLINE", text = "Soft" }
    end
    if flags.includeMono then
        opts[#opts + 1] = { key = "MONOCHROME",  text = "Monochrome" }
    end
    return opts
end

-- Outline values saved while the per-module Slug modes existed are no longer
-- selectable. A dropdown handed an unknown key renders the raw key as its
-- label, so every read site funnels stored values through here first.
local RETIRED_OUTLINES = {
    ["SLUG"] = "NONE",
    ["SLUG,OUTLINE"] = "OUTLINE",
    ["OUTLINE, SLUG"] = "OUTLINE",
}

---@param value string?
---@return string
function KE:NormalizeFontOutline(value)
    if value == nil then return "OUTLINE" end
    return RETIRED_OUTLINES[value] or value
end

---------------------------------------------------------------------------------
-- Slug Gate
---------------------------------------------------------------------------------
-- SLUG is Blizzard's GPU glyph renderer, not an outline effect, so an enabled
-- gate slugs plain text too. THICKOUTLINE and MONOCHROME are left alone: the
-- first renders badly slugged, the second carries its own rasterization rules.
-- The disabled path strips rather than short-circuits, so an outline value
-- saved while the old per-module Slug dropdown existed degrades to its plain
-- form instead of sticking.
--
-- Slug silently draws nothing against the large CJK and Cyrillic faces these
-- clients ship, which reads as a missing font rather than a missing effect.
-- GetLocale is called inline, not localized at file scope, so headless specs
-- can vary it per example.
local SLUG_UNSUPPORTED = { zhCN = true, zhTW = true, koKR = true, ruRU = true }

-- Slug strokes an outline in proportion to the glyph, where the bitmap
-- rasterizer draws a fixed thin edge at every height. Past this size the ring
-- reads as a heavy border rather than an outline, so large outlined text keeps
-- the bitmap edge. Blizzard's own slug-plus-outline font families stop here for
-- the same reason. Plain and shadowed text is unaffected and slugs at any size.
local SLUG_OUTLINE_MAX_SIZE = 24

---@param flags string?
---@param size number? font height; only consulted for outlined text
---@return string?
function KE:SlugFlags(flags, size)
    local locale = GetLocale and GetLocale() or "enUS"
    local profile = self.db and self.db.profile
    local enabled = not SLUG_UNSUPPORTED[locale] and profile ~= nil and profile.UseSlugFonts == true

    if enabled then
        flags = flags or ""
        if flags:find("SLUG", 1, true) then return flags end
        if flags:find("THICKOUTLINE", 1, true) or flags:find("MONOCHROME", 1, true) then
            return flags
        end
        if size and size > SLUG_OUTLINE_MAX_SIZE and flags:find("OUTLINE", 1, true) then
            return flags
        end
        if flags == "" then return "SLUG" end
        return flags .. ", SLUG"
    end

    if not flags or flags == "" then return flags end
    if not flags:find("SLUG", 1, true) then return flags end
    -- Strips the concatenated form and the leading legacy form. Parenthesized
    -- so the gsub match count never leaks out as a second return value.
    return (flags:gsub("%s*,%s*SLUG", ""):gsub("^%s*SLUG%s*,?%s*", ""):gsub("SLUG", ""))
end

---------------------------------------------------------------------------------
-- Font Validation
---------------------------------------------------------------------------------
-- TODO: 12.0.7 introduces a native font/asset validation API; until then,
-- a hidden FontString + pcall(SetFont) is the most reliable probe.

local fontProbe = UIParent:CreateFontString()
fontProbe:Hide()

local DEFAULT_FONT = "Expressway"

function KE:IsFontValid(fontPath)
    if not fontPath or fontPath == "" then return false end
    return pcall(fontProbe.SetFont, fontProbe, fontPath, 12, "")
end

-- Match KE's flat-DB font key convention. New modules adding a font reference
-- should use one of these key shapes so ValidateProfileFonts repairs them.
local function IsFontKey(key)
    if type(key) ~= "string" then return false end
    return key == "Font" or key:match("FontFace$")
end

local function ValidateFontsRecursive(tbl, defaults)
    if type(tbl) ~= "table" then return end
    local LSM = KE.LSM
    if not LSM then return end

    for key, value in pairs(tbl) do
        if IsFontKey(key) and type(value) == "string" then
            -- An empty font key whose own default is empty is a deliberate
            -- "use the addon's font" choice, not a broken value. Repairing it
            -- would write a font name into every profile on every login.
            local wantsEmpty = value == "" and (defaults and defaults[key]) == ""
            if not wantsEmpty and not LSM:IsValid("font", value) then
                local defaultVal = defaults and defaults[key] or KE:GetGlobalFont()
                if not LSM:IsValid("font", defaultVal) then
                    -- Backstop stays a literal. KE registers Expressway itself,
                    -- so it is the one name guaranteed valid. The global font is
                    -- never validated -- IsFontKey matches only "Font" and keys
                    -- ending FontFace, so "GlobalFont" is not a font key -- which
                    -- means it can BE the invalid value this branch just rejected.
                    defaultVal = DEFAULT_FONT
                end
                tbl[key] = defaultVal
            end
        elseif type(value) == "table" then
            local subDefaults = defaults and defaults[key]
            ValidateFontsRecursive(value, subDefaults)
        end
    end
end

function KE:ValidateProfileFonts()
    if not self.db or not self.db.profile then return end
    local defaults = self.db.defaults and self.db.defaults.profile
    ValidateFontsRecursive(self.db.profile, defaults)
end

-- AceDB defaults backfill works at the top profile level via __index, but it
-- does NOT deep-fill missing keys inside nested sub-tables that already exist
-- in saved data. When a new key (e.g. `DeathNotifications.FocusDeath`) is
-- added to defaults after a profile was saved, the old profile's nested table
-- stays missing that key, and code that does `db.DeathNotifications.FocusDeath.Enabled`
-- crashes with "attempt to index field (a nil value)". CopyMissingKeys walks
-- defaults and copies any missing key into saved, recursing into sub-tables.
local function CopyMissingKeys(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(tbl[k]) ~= "table" then tbl[k] = {} end
            CopyMissingKeys(tbl[k], v)
        elseif tbl[k] == nil then
            tbl[k] = v
        end
    end
end

function KE:FillProfileDefaults()
    if not self.db or not self.db.profile then return end
    local defaults = self.db.defaults and self.db.defaults.profile
    if not defaults then return end
    CopyMissingKeys(self.db.profile, defaults)
end

---------------------------------------------------------------------------------
-- Color Resolution
---------------------------------------------------------------------------------
-- AceDB stores user-edited color tables sparsely (e.g. {[3]=0.549}) when only
-- one channel was changed via the GUI, and may leave the whole table missing
-- after a profile reset. ResolveColor returns r,g,b,a as four values, falling
-- back to the caller-supplied default per index. Callers should pass the same
-- default array they ship in Defaults.lua.
---@param saved number[]?
---@param default number[]
---@return number r
---@return number g
---@return number b
---@return number a
function KE:ResolveColor(saved, default)
    if not saved then
        return default[1], default[2], default[3], default[4] or 1
    end
    return saved[1] or default[1],
           saved[2] or default[2],
           saved[3] or default[3],
           saved[4] or default[4] or 1
end

---@param fontString FontString
---@param fontName string
---@param fontSize number
---@param fontOutline string?
---@return boolean
function KE:ApplyFont(fontString, fontName, fontSize, fontOutline)
    if not fontString then return false end
    local fontPath = self:GetFontPath(fontName)
    if not self:IsFontValid(fontPath) then
        fontPath = "Fonts\\FRIZQT__.TTF"
    end
    local size = (fontSize and fontSize > 0) and fontSize or 12
    local outline = self:SlugFlags(self:GetFontOutline(fontOutline), size)

    -- SimpleHTML frames (guild MOTD and Info bodies, anything rendering
    -- links) expose SetFont with a textType-FIRST signature:
    -- SetFont(textType, fontFile, height, flags). Calling the
    -- FontString form on one throws "bad argument #1". Callers cannot tell
    -- the two apart by testing for SetFont, because both have it, so the
    -- branch belongs here. Each text type is pcall'd: the set below is not
    -- enumerated in the generated docs, so an unsupported one must not throw.
    if fontString.IsObjectType and fontString:IsObjectType("SimpleHTML") then
        for _, textType in ipairs({ "p", "h1", "h2", "h3" }) do
            pcall(fontString.SetFont, fontString, textType, fontPath, size, outline)
        end
        return true
    end

    ---@cast fontString FontString
    local success = fontString:SetFont(fontPath, size, outline)
    if not success then
        success = fontString:SetFont("Fonts\\FRIZQT__.TTF", size, outline)
    end
    return success
end

---------------------------------------------------------------------------------
-- Text Justification
---------------------------------------------------------------------------------

function KE:GetTextJustifyFromAnchor(anchorPoint)
    if not anchorPoint then return "CENTER" end
    if anchorPoint == "RIGHT" or anchorPoint == "TOPRIGHT" or anchorPoint == "BOTTOMRIGHT" then
        return "RIGHT"
    elseif anchorPoint == "LEFT" or anchorPoint == "TOPLEFT" or anchorPoint == "BOTTOMLEFT" then
        return "LEFT"
    end
    return "CENTER"
end

function KE:GetTextPointFromAnchor(anchorPoint)
    local justify = self:GetTextJustifyFromAnchor(anchorPoint)
    if justify == "RIGHT" then return "RIGHT"
    elseif justify == "LEFT" then return "LEFT" end
    return "CENTER"
end

-- Simple 3-way anchor → point mapping: LEFT/RIGHT pass through, everything else → CENTER.
-- Differs from GetTextPointFromAnchor by NOT expanding TOPRIGHT/BOTTOMRIGHT to RIGHT.
function KE:GetPointFromAnchor(anchor)
    if anchor == "LEFT" then return "LEFT"
    elseif anchor == "RIGHT" then return "RIGHT"
    end
    return "CENTER"
end

---------------------------------------------------------------------------------
-- Preview Manager
---------------------------------------------------------------------------------

local PreviewManager = {}
KE.PreviewManager = PreviewManager

local PREVIEW_MODULES = {
    "StanceText", "CombatCross", "CombatTexts", "CombatRes",
    "CombatTimer", "PetStatusText", "DragonRiding",
    "FocusCastbar", "RaidNotifications", "HuntersMark", "RangeChecker",
    "TimeSpiral", "TotemTracker", "DisintegrateTicks", "StasisTracker", "Recuperate", "KickTracker",
    "NoMovementAlert", "PrescienceTracker", "GreatVaultAlert", "PotionReady", "AuraExternals", "AuraDebuffs",
    "EnemyCounter", "EbonMightTracker", "DungeonCasts", "HealerMana", "InnervateTracker", "MaintenanceTracker",
    "ReadyCheckConsumables", "DeathNotifications",
    "BurningRush",
    "Cursor",
    "DamageMeter",
    "MythicPlusTimer", "KeystoneHelper", "TargetedSpells", "LFGReminder",
    "PlayerAbsorbs",
    -- Membership means "has ShowPreview/HidePreview". Chat and AlertFrames
    -- were listed here and define neither, so both were inert; LootRoll
    -- defines both (Modules/Skinning/LootRollBars.lua) and was missing, so
    -- /kes edit showed its mover with no sample bars behind it.
    "LootRoll",
}

-- Section → preview module mapping for section-based previews
-- Sections not listed here (Settings, Optimize) have no previews
local SECTION_PREVIEW_MODULES = {
    combat_section = {
        "CombatRes", "CombatTexts", "CombatTimer",
        "FocusCastbar", "CombatCross", "RangeChecker",
        "Cursor",
        "HealerMana", "InnervateTracker", "MaintenanceTracker",
        "NoMovementAlert", "PlayerAbsorbs",
    },
    aura_section = {
        "AuraDebuffs", "AuraExternals", "StanceText",
    },
    class_section = {
        "BurningRush",
        "PetStatusText", "TotemTracker",
        "DisintegrateTicks", "StasisTracker", "EbonMightTracker", "PrescienceTracker",
        "HuntersMark",
    },
    qol_section = {
        "GreatVaultAlert",
        "PotionReady", "RaidNotifications", "Recuperate",
        "TimeSpiral", "ReadyCheckConsumables",
    },
    -- Skyriding UI moved here from Quality of Life. Without this entry the
    -- module stays in PREVIEW_MODULES but no section reaches it, so opening its
    -- page would show no preview at all.
    skinning_section = {
        "DragonRiding",
        "DamageMeter", "MythicPlusTimer",
    },
    dungeons_section = {
        "EnemyCounter", "KickTracker", "DungeonCasts", "DeathNotifications",
        "KeystoneHelper", "TargetedSpells", "LFGReminder",
    },
}

-- Reverse lookup: sidebar item ID → section ID (built lazily)
local ITEM_TO_SECTION = nil

local function GetItemToSection()
    if ITEM_TO_SECTION then return ITEM_TO_SECTION end
    ITEM_TO_SECTION = {}
    local GUIFrame = KE.GUIFrame
    local sidebarConfig = GUIFrame and GUIFrame.sidebarConfig
    if sidebarConfig then
        for _, section in ipairs(sidebarConfig) do
            if section.items then
                for _, item in ipairs(section.items) do
                    ITEM_TO_SECTION[item.id] = section.id
                end
            end
        end
    end
    return ITEM_TO_SECTION
end

PreviewManager.guiOpen = false
PreviewManager.editModeActive = false
PreviewManager.previewsActive = false
PreviewManager.activeSection = nil

-- Per-module preview state cache (moduleName → "preview" | "hidden") so
-- ShowSectionPreviews / ShowModules only fire module:ShowPreview /
-- :HidePreview when the state actually changes. Without this, every
-- cross-section GUI nav re-fires ShowPreview on every preview module —
-- modules like RaidNotifications redundantly re-apply fonts/colors/sizes
-- to all rows on each transition. Wiped on StopAllPreviews so the next
-- show does fresh setup.
PreviewManager._moduleStates = {}

function PreviewManager:UpdatePreviewState()
    if self.editModeActive then
        -- Edit mode: show ALL previews regardless of section
        self:ShowModules(PREVIEW_MODULES)
        self.previewsActive = true
        return
    end

    if self.guiOpen then
        -- GUI open: show only the active section's previews
        self.previewsActive = true
        self:ShowSectionPreviews(self.activeSection)
    elseif self.previewsActive then
        self:StopAllPreviews()
        self.previewsActive = false
    end
end

function PreviewManager:SetGUIOpen(open)
    self.guiOpen = open
    self:UpdatePreviewState()
end

function PreviewManager:SetEditModeActive(active)
    self.editModeActive = active
    self:UpdatePreviewState()
end

function PreviewManager:SetActiveSection(sectionId)
    if self.activeSection == sectionId then return end
    self.activeSection = sectionId
    if self.guiOpen and not self.editModeActive then
        self:ShowSectionPreviews(sectionId)
    end
end

-- Resolve section from a sidebar item ID and activate it
function PreviewManager:SetActivePage(itemId)
    local lookup = GetItemToSection()
    local sectionId = lookup[itemId]
    self:SetActiveSection(sectionId)
end

-- Called from the EnableModule/DisableModule hooks (Core/Main.lua) when a
-- module's enable state flips. The _moduleStates cache pins the last
-- show/hide decision, so a module toggled off and back on while its GUI
-- section is on screen would otherwise keep its stale "preview" entry and
-- not re-preview until the next section change. Clearing the one entry and
-- re-running the state machine lets ShowSectionPreviews decide fresh —
-- section wanting, db.Enabled, and class restriction still apply, so
-- non-applicable-class modules stay silent (project convention).
function PreviewManager:OnModuleEnableChanged(moduleName)
    if not (self.guiOpen or self.editModeActive) then return end
    if InCombatLockdown() then return end
    self._moduleStates[moduleName] = nil
    self:UpdatePreviewState()
end

function PreviewManager:ShowSectionPreviews(sectionId)
    local Addon = KitnEssentials
    if not Addon then return end

    local wantedModules = sectionId and SECTION_PREVIEW_MODULES[sectionId]
    local wantedSet = {}
    if wantedModules then
        for _, name in ipairs(wantedModules) do
            wantedSet[name] = true
        end
    end

    local classMatch = { [select(2, UnitClass("player"))] = true }
    local states = self._moduleStates

    for _, moduleName in ipairs(PREVIEW_MODULES) do
        local module = Addon:GetModule(moduleName, true)
        if module then
            local wantPreview = wantedSet[moduleName]
                and module.ShowPreview and module.db and module.db.Enabled
                and (not module.classRestriction or classMatch[module.classRestriction])
            if wantPreview then
                if states[moduleName] ~= "preview" then
                    module:ShowPreview()
                    states[moduleName] = "preview"
                end
            elseif module.HidePreview then
                if states[moduleName] ~= "hidden" then
                    module:HidePreview()
                    states[moduleName] = "hidden"
                end
            end
        end
    end
end

function PreviewManager:ShowModules(moduleList)
    local Addon = KitnEssentials
    if not Addon then return end
    local classMatch = { [select(2, UnitClass("player"))] = true }
    local states = self._moduleStates
    for _, moduleName in ipairs(moduleList) do
        local module = Addon:GetModule(moduleName, true)
        if module and module.ShowPreview and module.db and module.db.Enabled then
            if not module.classRestriction or classMatch[module.classRestriction] then
                if states[moduleName] ~= "preview" then
                    module:ShowPreview()
                    states[moduleName] = "preview"
                end
            end
        end
    end
end

function PreviewManager:StopAllPreviews()
    local Addon = KitnEssentials
    if not Addon then return end
    local states = self._moduleStates
    for _, moduleName in ipairs(PREVIEW_MODULES) do
        local module = Addon:GetModule(moduleName, true)
        if module and module.HidePreview then
            if states[moduleName] ~= "hidden" then
                module:HidePreview()
                states[moduleName] = "hidden"
            end
        end
    end
end

function PreviewManager:IsPreviewActive()
    return self.previewsActive
end

---------------------------------------------------------------------------------
-- EllesmereUI themed character sheet
---------------------------------------------------------------------------------
-- EUI's Blizz UI Enhanced does not skin the character sheet, it REPLACES it:
-- it hides Blizzard's slot wrappers, re-anchors every slot into its own
-- two-column grid, swaps the model, and draws its own per-slot item level,
-- upgrade track, enchant and gem icons (EllesmereUIBlizzardSkin_CharacterSheet.lua,
-- and _InspectSheet.lua for the inspect frame). Its column sides happen to match
-- ours almost exactly, so KE's own per-slot text lands on top of EUI's rather
-- than beside it.
--
-- CharacterPanel / InspectPanel therefore stand down from the overlapping
-- display while this is live, the same way they already stand down for ElvUI.
-- Everything EUI does NOT draw (the socket helper, inspect gems, race text,
-- the faction tag) keeps running.
--
-- The test is EUI's OWN gate, copied from the places it guards each sheet with,
-- so turning a themed sheet off hands that display straight back to us. Absent
-- means ON -- only a literal false is off, EUI's convention.
--
-- The two sheets have SEPARATE enable keys and separate user-facing toggles, so
-- they really do diverge by a click. Gating the inspect frame on the character sheet's key
-- breaks both ways: inspect text vanishes when only the inspect sheet is off,
-- and double-draws when only the character sheet is off. Pass the unit and let
-- this pick, rather than leaving the choice to each call site.
---@param unit string? "player" selects the character sheet; anything else, inspect
function KE:EUISheetActive(unit)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")) then
        return false
    end
    local db = _G.EllesmereUIDB
    local key = (unit == nil or unit == "player") and "themedCharacterSheet"
        or "themedInspectSheet"
    if type(db) == "table" and db[key] == false then return false end
    -- EUI's master "no Blizzard window skins" switch, which kills both sheets
    -- at once. Guarded: it is a function on EUI's own namespace, absent in
    -- older builds.
    local eui = _G.EllesmereUI
    if eui and type(eui.BlizzWindowSkinsKilled) == "function" then
        local ok, killed = pcall(eui.BlizzWindowSkinsKilled)
        if ok and killed then return false end
    end
    return true
end

-- Whether EUI is drawing ONE PARTICULAR per-slot element on a given frame.
--
-- The sheet being on is not enough to decide ownership: EUI ships six
-- independent per-element toggles on top of it, all live and all user-facing.
-- Standing down on the sheet alone means turning EUI's "Show Gems"
-- off deletes the gems from BOTH addons -- strictly worse than the doubling
-- this was meant to solve. Ask per element instead.
--
-- Two asymmetries in EUI worth knowing, both verified in its source:
--   * gems: the inspect sheet draws none at all, at any setting.
--   * missingEnchant: on the CHARACTER sheet the pulsing red border fires
--     outside the showEnchants branch, so EUI
--     still flags a missing enchant with enchant display off. The INSPECT
--     sheet has no border -- icon only, and that icon IS gated -- so with
--     inspectShowEnchants off nothing marks it and ours should show.
--
-- Absent means ON throughout, EUI's own convention.
local EUI_ELEMENT_KEYS = {
    player = {
        ilvl = "showItemLevel", enchant = "showEnchants",
        gems = "showGems",     track   = "showUpgradeTrack",
        -- EUI's own bottom-of-sheet socket row (SocketPanel.lua), the same
        -- feature as KE's socket bar down to the click-to-flyout behaviour.
        socketPanel = "charSheetSocketPanel",
    },
    inspect = {
        ilvl = "inspectShowItemLevel", enchant = "inspectShowEnchants",
        track = "inspectShowUpgradeTrack",
        -- gems deliberately absent: see above.
    },
}

---@param unit string? "player" selects the character sheet; anything else, inspect
---@param element string "ilvl" | "enchant" | "gems" | "track" | "missingEnchant"
function KE:EUIDrawsSlotElement(unit, element)
    if not self:EUISheetActive(unit) then return false end
    local isPlayer = (unit == nil or unit == "player")

    if element == "missingEnchant" then
        -- Character sheet: the border is unconditional, so EUI always marks it.
        if isPlayer then return true end
        element = "enchant"  -- inspect: rides entirely on the enchant icon
    end

    -- Elements EUI ships with NO switch of its own. The sheet being active IS
    -- the answer for these, so they never reach the key table below.
    if element == "headerText" then
        -- Character sheet only. EUI re-anchors Blizzard's own name and level
        -- strings into its header rather than drawing its own. KE restyling
        -- them and displacing the level string to make room for race text
        -- lands on top of that, and the two overlap on screen.
        return isPlayer
    end
    if element == "avgIlvl" then
        -- INSPECT only, and deliberately not the character sheet: there KE's
        -- decimal item level feeds EUI's own readout rather than drawing a
        -- second one, so it is an enhancement, not a duplicate. On inspect EUI
        -- prints its own average and ours lands under the Talents button.
        return not isPlayer
    end

    local keys = isPlayer and EUI_ELEMENT_KEYS.player or EUI_ELEMENT_KEYS.inspect
    local key = keys[element]
    if not key then return false end  -- EUI never draws this element on this frame

    local db = _G.EllesmereUIDB
    return not (type(db) == "table" and db[key] == false)
end

---------------------------------------------------------------------------------
-- Healer Position Override
---------------------------------------------------------------------------------

function KE:IsPlayerHealerSpec()
    local specIndex = _G.GetSpecialization()
    if not specIndex then return false end
    local role = _G.GetSpecializationRole(specIndex)
    return role == "HEALER"
end

-- forceContext (optional): "HEALER" / "DEFAULT" overrides the live spec-driven
-- resolution — used by the GUI to edit/preview a context regardless of the
-- player's current spec. When nil, resolves live (UseHealerPosition + healer).
function KE:GetActivePositionConfig(db, forceContext)
    local useHealer
    if forceContext ~= nil then
        useHealer = (forceContext == "HEALER")
    else
        useHealer = db.UseHealerPosition and self:IsPlayerHealerSpec()
    end
    if useHealer and db.HealerPosition then
        return db.HealerPosition,
               db.HealerAnchorFrameType or db.anchorFrameType,
               db.HealerParentFrame or db.ParentFrame,
               db.HealerStrata or db.Strata
    end
    return db.Position, db.anchorFrameType, db.ParentFrame, db.Strata
end

function KE:ApplyActivePosition(frame, db, setParent)
    local posConfig, aft, pf, strata = self:GetActivePositionConfig(db)
    local config = { anchorFrameType = aft, ParentFrame = pf, Strata = strata }
    self:ApplyFramePosition(frame, posConfig, config, setParent)
end

function KE:ApplyFramePosition(frame, posConfig, Config, SetParent)
    if not frame or not posConfig then return end
    local parent = self:ResolveAnchorFrame(Config.anchorFrameType, Config.ParentFrame)
    if SetParent then
        frame:SetParent(parent)
    end
    frame:ClearAllPoints()
    frame:SetPoint(
        posConfig.AnchorFrom or "CENTER",
        parent,
        posConfig.AnchorTo or "CENTER",
        posConfig.XOffset or 0,
        posConfig.YOffset or 0
    )
    frame:SetFrameStrata(Config.Strata or "MEDIUM")
    self:SnapFrameToPixels(frame)
end
