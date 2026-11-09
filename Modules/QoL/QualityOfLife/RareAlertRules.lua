-- ╔══════════════════════════════════════════════════════════╗
-- ║  RareAlertRules.lua                                      ║
-- ║  Module: Rare Alert                                      ║
-- ║  Purpose: the alert's pure decisions (what fires, what   ║
-- ║           replaces what, the arrow, the card's third     ║
-- ║           line, the party line). No WoW API calls.       ║
-- ╚══════════════════════════════════════════════════════════╝

if not KitnEssentials then return end

---@class RareAlert: AceModule, AceEvent-3.0
local RA = KitnEssentials:GetModule("RareAlert")

local atan2 = math.atan2
local sqrt = math.sqrt
local format = string.format

---------------------------------------------------------------------------------
-- What fires
---------------------------------------------------------------------------------
local SOURCE_TICK = {
    vignette = "FireVignette",
    plate = "FirePlate",
    target = "FireTarget",
    mouseover = "FireTarget",
}

function RA.Decide(fact, settings)
    if not settings[SOURCE_TICK[fact.source]] then return "none" end
    if not fact.npc or not fact.isRare or not fact.hostile then return "none" end
    if fact.dead or fact.friendly or fact.seenRecently then return "none" end
    if fact.source == "vignette" and fact.provedWrong then return "none" end

    local found = fact.source == "target" or fact.source == "mouseover"
    local quiet = (fact.tapped and not settings.LoudTapped)
        or (fact.gray and not settings.LoudGray)
        or (found and not settings.LoudFound)
    if not quiet then return "loud" end
    return settings.ShowQuiet and "quiet" or "none"
end

-- With no table every rare is "not known", so the atlas alone decides.
function RA.VignetteCounts(npc, onMinimap, dead, known, friendly, killAtlas)
    if not npc or not onMinimap or dead then return false end
    if known then return not friendly end
    return killAtlas and true or false
end

---------------------------------------------------------------------------------
-- Repeats and replacing
---------------------------------------------------------------------------------
RA.AGAIN_AFTER = 300

function RA.SeenRecently(seen, npc, now)
    local last = seen[npc]
    return last ~= nil and now - last < RA.AGAIN_AFTER
end

function RA.Stamp(seen, npc, now)
    seen[npc] = now
end

function RA.Replaces(incoming, shown)
    if shown == nil or shown == "preview" then return true end
    if incoming == "loud" then return true end
    return shown == "quiet"
end

---------------------------------------------------------------------------------
-- The arrow
---------------------------------------------------------------------------------
-- Map x grows east and y grows south; facing is radians counterclockwise from
-- north. The rotation is what SetRotation takes for an arrow drawn pointing up.
function RA.Bearing(px, py, vx, vy, worldW, worldH, facing)
    if not (px and py and vx and vy and worldW and worldH and facing) then return nil end
    if worldW <= 0 or worldH <= 0 then return nil end
    local dx = (vx - px) * worldW
    local dy = (vy - py) * worldH
    return atan2(-dx, -dy) - facing, sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------------
-- The card's third line
---------------------------------------------------------------------------------
function RA.ThirdLine(state)
    if state.targeted and not state.dead then return "targeted" end
    if state.tapped and not state.dead and not state.combat then return "tapped" end
    if state.dead then return "dead" end
    if state.left then return "left" end
    if state.combat then return "combat" end
    if state.drop then return "drop" end
    if not state.unitSeen then return "far" end
    return "click"
end

local function Beats(item, best)
    local itemQuality, bestQuality = item.quality or 0, best.quality or 0
    if itemQuality ~= bestQuality then return itemQuality > bestQuality end
    if item.new and not best.new then return true end
    if best.new and not item.new then return false end
    return (item.chance or 0) > (best.chance or 0)
end

function RA.BestDrop(loot)
    if not loot then return nil end
    local best
    for i = 1, #loot do
        if not best or Beats(loot[i], best) then best = loot[i] end
    end
    return best
end

---------------------------------------------------------------------------------
-- The party line
---------------------------------------------------------------------------------
function RA.PartyAllowed(setting, decision, inGroup, inRaid, inCombat, chatLocked)
    if not setting or decision ~= "loud" or not inGroup then return false end
    if inRaid or inCombat or chatLocked then return false end
    return true
end

function RA.PartyLine(name, levelText, elite, x, y)
    local line = "Rare: " .. name:gsub("[%c|]", "")
    if levelText then
        line = line .. ", level " .. levelText .. (elite and " elite" or "")
    elseif elite then
        line = line .. ", elite"
    end
    if x and y then
        line = line .. format(", at %.1f, %.1f", x, y)
    end
    return line
end

---------------------------------------------------------------------------------
-- Small reads
---------------------------------------------------------------------------------
function RA.NpcOf(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

function RA.LevelText(low, high)
    if not low or low <= 0 then return nil end
    if high and high > low then return low .. "-" .. high end
    return tostring(low)
end
