-- ╔══════════════════════════════════════════════════════════╗
-- ║  Tags-UUF.lua                                            ║
-- ║  Purpose: Register the kes:nickname tag family with      ║
-- ║           Unhalted Unit Frames (UUF) when present.       ║
-- ║  Timing: Must register BEFORE UUF's OnEnable so frame    ║
-- ║          spawning can resolve [kes:nickname] strings in  ║
-- ║          user configs. We register at UUF's own          ║
-- ║          ADDON_LOADED (or immediately if UUFG is already ║
-- ║          present at our file-parse), which both fire     ║
-- ║          before any OnEnable. CRITICAL: never call       ║
-- ║          C_AddOns.LoadAddOn here — that synchronously    ║
-- ║          triggers UUF's init mid-our-init and corrupts   ║
-- ║          shared Ace3 state (see the                      ║
-- ║          feedback_loadaddon_init_timing memory). We only ║
-- ║          touch UUFG when it's already fully initialized. ║
-- ║  Note: Isolated from Tags.lua so the ElvUI path is       ║
-- ║        untouched by UUF support. Duplicates a small      ║
-- ║        helper block (~15 lines) for that isolation.      ║
-- ╚══════════════════════════════════════════════════════════╝
---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local UnitName = UnitName
local UnitFullName = UnitFullName
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local GetNormalizedRealmName = GetNormalizedRealmName
local strsub = string.sub
local format = string.format
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

---------------------------------------------------------------------------------
-- Helpers (mirror of Tags.lua's nickname block — kept local for isolation)
---------------------------------------------------------------------------------

local function GetNicknameKey(unit)
    local name, realm = UnitFullName(unit)
    if not name or name == '' then return nil end
    if not realm or realm == '' then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == '' then return nil end
    return name .. '-' .. realm
end

local function GetNicknameOrName(unit)
    if not UnitIsPlayer(unit) then
        return UnitName(unit)
    end
    local nicknames = KE and KE.db and KE.db.global and KE.db.global.Nicknames
    if nicknames then
        local key = GetNicknameKey(unit)
        if key then
            local nick = nicknames[key]
            if nick and nick ~= '' then
                return nick
            end
        end
    end
    return UnitName(unit)
end

-- UUF delegates UTF-8 truncation to DetailsFramework when available (see
-- UUF/Core/Globals.lua `UUF:CleanTruncateUTF8String`). Mirror that pattern so
-- our width variants behave identically to UUF's native `name:short:N` tags:
-- byte-level cut for ASCII, codepoint-clean boundary when DF is loaded.
-- Falls back to raw strsub if DF is absent (same behavior UUF itself degrades
-- to).
local function Truncate(str, n)
    if not str then return nil end
    local truncated = strsub(str, 1, n)
    local DF = _G.DF
    if DF and DF.CleanTruncateUTF8String then
        return DF:CleanTruncateUTF8String(truncated)
    end
    return truncated
end

---------------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------------
-- UUFG:AddTag(name, event, fn, category, description) — 5-arg signature.
-- Category "Name" adds the tag to UUF's tag browser under the Name section.
-- Any other category string (e.g. "Hidden") causes UUFG:AddTag to early-return
-- without adding a browser entry while still registering the tag method —
-- lets us expose a clean 4-entry browser while 68 width/colour variants work
-- behind the scenes. Mirrors UUF's own pattern: [name:short:10] is listed as
-- representative for the 1-25 range even though each width is registered.

local NICK_EVENTS = 'UNIT_NAME_UPDATE GROUP_ROSTER_UPDATE'
local VISIBLE_CATEGORY = 'Name'
local HIDDEN_CATEGORY = 'Hidden'

-- Wrap the nickname value in a class-color code when the unit is a player.
-- NPCs and missing classes fall through uncolored; matches UUF's own
-- [name:colour] behaviour (UUF uses its internal GetUnitColour helper, which
-- we can't access from outside — but it reads the same RAID_CLASS_COLORS
-- table Blizzard exposes globally). Note: we use American spelling `color`
-- in our tag names (`kes:nickname:color`) to match ElvUI's convention even
-- though UUF's own tags use the British `colour` — each frame lib picks
-- whichever it registered, and our tags live in their own namespace.
local function Colorize(str, unit)
    if not UnitIsPlayer(unit) then return str end
    local _, class = UnitClass(unit)
    if not class then return str end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return str end
    return format('|cff%02x%02x%02x%s|r', c.r * 255, c.g * 255, c.b * 255, str)
end

local function MakeTagFn(lengthOrNil, colored)
    return function(unit)
        local s = GetNicknameOrName(unit)
        if not s then return nil end
        if lengthOrNil then s = Truncate(s, lengthOrNil) end
        if not s then return nil end
        if colored then return Colorize(s, unit) end
        return s
    end
end

local function RegisterNicknameTagsWithUUF()
    local UUFG = _G.UUFG
    if not UUFG or not UUFG.AddTag then return end

    local function addVisible(name, lengthOrNil, colored, info)
        UUFG:AddTag(name, NICK_EVENTS, MakeTagFn(lengthOrNil, colored),
            VISIBLE_CATEGORY, "[KES] " .. info)
    end
    local function addHidden(name, lengthOrNil, colored)
        UUFG:AddTag(name, NICK_EVENTS, MakeTagFn(lengthOrNil, colored),
            HIDDEN_CATEGORY, "")
    end

    -- 4 visible entries cover the full shape of what's available:
    addVisible('kes:nickname',          nil, false, "Nickname if set, else unit name")
    addVisible('kes:nickname:10',       10,  false, "Nickname shortened (1-30 chars)")
    addVisible('kes:nickname:color',    nil, true,  "Nickname with class color")
    addVisible('kes:nickname:color:10', 10,  true,  "Nickname shortened + class color (1-30 chars)")

    -- Hidden numeric widths 1-30 for both uncolored and colored variants
    -- (skip :10 and :color:10 — already registered as visible primaries).
    for n = 1, 30 do
        if n ~= 10 then
            addHidden('kes:nickname:' .. n,        n, false)
            addHidden('kes:nickname:color:' .. n,  n, true)
        end
    end

    -- Named aliases for uncolored + colored. Kept hidden — users find the
    -- numeric representative in the browser and this set is documentation /
    -- parity with the ElvUI side.
    addHidden('kes:nickname:short',        6,  false)
    addHidden('kes:nickname:medium',       10, false)
    addHidden('kes:nickname:long',         20, false)
    addHidden('kes:nickname:color:short',  6,  true)
    addHidden('kes:nickname:color:medium', 10, true)
    addHidden('kes:nickname:color:long',   20, true)
end

-- Dual-path registration covering both addon load orders:
--   1. UUF loads before us — UUFG already exists at our file-parse, register
--      immediately. Safe because we're only calling UUFG:AddTag (pure data
--      insertion into an already-initialized object), not LoadAddOn.
--   2. UUF loads after us — UUFG isn't present yet; wait for its ADDON_LOADED
--      event and register then. ADDON_LOADED for "UnhaltedUnitFrames" fires
--      after UUF's files are parsed (UUFG populated) but before any
--      OnEnable, so our tags exist in time for UUF's frame-spawning pass.
local function Register()
    if _G.UUFG and _G.UUFG.AddTag then
        RegisterNicknameTagsWithUUF()
        return true
    end
    return false
end

if not Register() then
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, _, addonName)
        if addonName == "UnhaltedUnitFrames" and Register() then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end
