-- KitnEssentials — Custom ElvUI Tags
-- Registers custom tags with ElvUI if present.
local _ = select(2, ...)

-- Only load if ElvUI is present
if not ElvUI then return end

local E = unpack(ElvUI)
local ElvUF = _G.ElvUF

-- Locals
local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitExists = UnitExists
local UnitInPartyIsAI = UnitInPartyIsAI
local format = string.format

local ElvUF_colors_class = ElvUF.colors.class
local ElvUF_colors_reaction = ElvUF.colors.reaction

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

-- [kes:name-classcolor]
-- Displays the unit's own name colored by class (players) or reaction (NPCs)
E:AddTag('kes:name-classcolor', 'UNIT_NAME_UPDATE UNIT_FACTION', function(unit)
    local name = UnitName(unit)
    if not name then return end
    return GetUnitColor(unit) .. name .. '|r'
end)
E:AddTagInfo('kes:name-classcolor', 'KitnEssentials', "Unit name with class/reaction color")

-- [kes:target:separator]
-- White » separator, only visible when the unit has a target
E:AddTag('kes:target:separator', 'UNIT_TARGET', function(unit)
    local targetUnit = unit .. 'target'
    if not UnitExists(targetUnit) then return end
    return ' |cFFffffff\194\187|r '
end)
E:AddTagInfo('kes:target:separator', 'KitnEssentials', "White » separator, hidden when no target")

-- [kes:target:name-classcolor]
-- Displays the unit's target name colored by class (players) or reaction (NPCs)
E:AddTag('kes:target:name-classcolor', 'UNIT_TARGET UNIT_FACTION', function(unit)
    local targetUnit = unit .. 'target'
    local name = UnitName(targetUnit)
    if not name then return end
    return GetUnitColor(targetUnit) .. name .. '|r'
end)
E:AddTagInfo('kes:target:name-classcolor', 'KitnEssentials', "Target name with class/reaction color")
