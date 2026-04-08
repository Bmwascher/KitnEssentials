-- ╔══════════════════════════════════════════════════════════╗
-- ║  Tags.lua                                                ║
-- ║  Purpose: Custom ElvUI unit frame tags — name with       ║
-- ║           class/reaction color, target separator, and    ║
-- ║           target name with class color.                  ║
-- ║  Note: ElvUI only. Skips loading if ElvUI is absent.     ║
-- ╚══════════════════════════════════════════════════════════╝
local _ = select(2, ...)

if not ElvUI then return end

local E = unpack(ElvUI)
local ElvUF = _G.ElvUF

local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitExists = UnitExists
local UnitInPartyIsAI = UnitInPartyIsAI
local format = string.format

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
