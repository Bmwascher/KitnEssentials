-- ╔══════════════════════════════════════════════════════════╗
-- ║  Tags.lua                                                ║
-- ║  Purpose: Custom ElvUI unit frame tags — name with       ║
-- ║           class/reaction color, target separator, target ║
-- ║           name with class color, and nickname lookup.    ║
-- ║  Note: ElvUI only. Skips loading if ElvUI is absent.     ║
-- ╚══════════════════════════════════════════════════════════╝
---@class KE
local KE = select(2, ...)

if not ElvUI then return end

local E = unpack(ElvUI)
local ElvUF = _G.ElvUF

local UnitName = UnitName
local UnitFullName = UnitFullName
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitExists = UnitExists
local UnitInPartyIsAI = UnitInPartyIsAI
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetNormalizedRealmName = GetNormalizedRealmName
local format = string.format
local strsub = string.sub

local ElvUF_colors_class = ElvUF.colors.class
local ElvUF_colors_reaction = ElvUF.colors.reaction

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

local function Hex(r, g, b)
    return format('|cff%02x%02x%02x', r * 255, g * 255, b * 255)
end

local function GetUnitColor(unit)
    if UnitIsPlayer(unit) or (UnitInPartyIsAI and UnitInPartyIsAI(unit)) then
        local _, unitClass = UnitClass(unit)
        if unitClass then
            local cs = ElvUF_colors_class[unitClass]
            if cs then
                return Hex(cs.r, cs.g, cs.b)
            end
        end
    else
        local reaction = UnitReaction(unit, 'player')
        if reaction then
            local cr = ElvUF_colors_reaction[reaction]
            if cr then
                return Hex(cr.r, cr.g, cr.b)
            end
        end
    end
    return '|cFFcccccc'
end

---------------------------------------------------------------------------------
-- Tag Registration
---------------------------------------------------------------------------------

E:AddTag('kes:name-classcolor', 'UNIT_NAME_UPDATE UNIT_FACTION', function(unit)
    local name = UnitName(unit)
    if not name then return end
    return GetUnitColor(unit) .. name .. '|r'
end)
E:AddTagInfo('kes:name-classcolor', 'KitnEssentials', "Unit name with class/reaction color")

E:AddTag('kes:target:separator', 'UNIT_TARGET', function(unit)
    local targetUnit = unit .. 'target'
    if not UnitExists(targetUnit) then return end
    return ' |cFFffffff\194\187|r '
end)
E:AddTagInfo('kes:target:separator', 'KitnEssentials', "White » separator, hidden when no target")

E:AddTag('kes:target:name-classcolor', 'UNIT_TARGET UNIT_FACTION', function(unit)
    local targetUnit = unit .. 'target'
    local name = UnitName(targetUnit)
    if not name then return end
    return GetUnitColor(targetUnit) .. name .. '|r'
end)
E:AddTagInfo('kes:target:name-classcolor', 'KitnEssentials', "Target name with class/reaction color")

E:AddTag('kes:group', 'GROUP_ROSTER_UPDATE', function()
    if not IsInRaid() then return end
    local playerName = UnitName('player')
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name == playerName then
            return 'Group: ' .. subgroup
        end
    end
end)
E:AddTagInfo('kes:group', 'KitnEssentials', "Shows 'Group: X' only while in a raid")

---------------------------------------------------------------------------------
-- Nickname Tags
---------------------------------------------------------------------------------
-- Lookup: KE.db.global.Nicknames["Fullname-NormalizedRealm"] -> "Nickname"
-- Falls back to UnitName when no nickname is set.
-- Only player units are considered; NPCs always return their normal name.

-- Build the lookup key. Realm portion uses GetNormalizedRealmName() which
-- strips spaces/apostrophes (e.g. "Area 52" -> "Area52"), matching the
-- format that NSRT/TLR use — keeps us compatible if we ever add import/export.
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

-- Shared by all kes:nickname* tags. UNIT_NAME_UPDATE covers name changes,
-- GROUP_ROSTER_UPDATE covers roster entry/exit.
local NICK_EVENTS = 'UNIT_NAME_UPDATE GROUP_ROSTER_UPDATE'

-- Registered tag names, used by RefreshNicknameTags to invalidate ElvUF's
-- per-unit tag cache after the nicknames table is edited.
local NICK_TAG_NAMES = {}

-- Prefer ElvUI's UTF-8 aware truncation so multi-byte names don't break.
local function Truncate(str, n)
    if not str then return nil end
    if E.ShortenString then return E:ShortenString(str, n) end
    return strsub(str, 1, n)
end

local function AddNicknameTag(name, lengthOrNil, info)
    E:AddTag(name, NICK_EVENTS, function(unit)
        local s = GetNicknameOrName(unit)
        if not s then return nil end
        if lengthOrNil then return Truncate(s, lengthOrNil) end
        return s
    end)
    E:AddTagInfo(name, 'KitnEssentials', info)
    NICK_TAG_NAMES[#NICK_TAG_NAMES + 1] = name
end

-- Full nickname
AddNicknameTag('kes:nickname', nil, "Nickname if set, else unit name")

-- Numeric variants: [kes:nickname:1] through [kes:nickname:30].
-- Any width without needing named aliases.
for n = 1, 30 do
    AddNicknameTag('kes:nickname:' .. n, n,
        "Nickname (or name), max " .. n .. " chars")
end

-- Named variants matching ElvUI's familiar [name:short|medium|long] convention
AddNicknameTag('kes:nickname:short',  6,  "Nickname (or name), max 6 chars")
AddNicknameTag('kes:nickname:medium', 10, "Nickname (or name), max 10 chars")
AddNicknameTag('kes:nickname:long',   20, "Nickname (or name), max 20 chars")

-- Refresh hook for GUI / slash commands to call after editing the nicknames
-- table. ElvUF caches tag results per unit; RefreshMethods invalidates the
-- cache so the next UNIT_NAME_UPDATE (or forced update) re-runs our function.
function KE:RefreshNicknameTags()
    if not ElvUF or not ElvUF.Tags or not ElvUF.Tags.RefreshMethods then return end
    for i = 1, #NICK_TAG_NAMES do
        ElvUF.Tags:RefreshMethods(NICK_TAG_NAMES[i])
    end
end
