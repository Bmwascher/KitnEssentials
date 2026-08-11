-- ╔══════════════════════════════════════════════════════════╗
-- ║  Tags.lua                                                ║
-- ║  Purpose: Custom ElvUI unit frame tags — name with       ║
-- ║           class/reaction color, target separator, target ║
-- ║           name with class color, raid group, and mana.   ║
-- ║  Note: ElvUI only. Skips loading if ElvUI is absent.     ║
-- ╚══════════════════════════════════════════════════════════╝

if not ElvUI then return end

local E = unpack(ElvUI)
local ElvUF = _G.ElvUF

local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitExists = UnitExists
local UnitInPartyIsAI = UnitInPartyIsAI
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local format = string.format
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local math_floor = math.floor

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

E:AddTag('kes:mana:percent', 'UNIT_POWER_FREQUENT UNIT_MAXPOWER UNIT_DISPLAYPOWER', function(unit)
    local max = UnitPowerMax(unit, Enum.PowerType.Mana)
    local cur = UnitPower(unit, Enum.PowerType.Mana)
    -- UnitPower/UnitPowerMax can return secret values on hostile/encounter
    -- targets in 12.0.5. Fail-closed visibly rather than propagating the
    -- secret into ElvUF's tag pipeline via SetText. The guard must run
    -- BEFORE the max == 0 compare — comparison against a non-nil value on a
    -- secret throws, so the old order crashed exactly the case the guard
    -- was written for.
    if issecretvalue and (issecretvalue(max) or issecretvalue(cur)) then return end
    if max == 0 then return end
    local pct = math_floor((cur / max) * 100)
    if pct >= 100 then return end
    return pct
end)
E:AddTagInfo('kes:mana:percent', 'KitnEssentials', "Mana percentage. Hidden at 100%.")
