-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrainingWaypoints.lua                                   ║
-- ║  Purpose: Names the nearest listed class trainer and     ║
-- ║           the nearest weapon master who teaches a skill. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local T = KE.Training or {}
KE.Training = T

local Rules = KE.TrainingRules

local C_Map = C_Map
local CreateVector2D = CreateVector2D
local ipairs, pcall = ipairs, pcall

local Route = {}
T.Route = Route

local SOURCE = "TrainingRoute"
local TEXT_AFTER_COMBAT = "Nearest trainer after combat"
local TEXT_NO_TRAINER = "No trainer is listed for your class and faction."
local TEXT_CLASS_TRAINER = "Taught by your class trainer"
local TEXT_SOME_MASTER = "Taught by a weapon master"
local TEXT_NO_MASTER = "No weapon master who teaches it is listed for your faction"

local trainers, masters, capitals
local worldCache = {}

local function IsCapital(map)
    return capitals[map] == true
end

local function MapToWorld(npc)
    return C_Map.GetWorldPosFromMapPos(npc[1], CreateVector2D(npc[2] / 100, npc[3] / 100))
end

local function WorldPos(npc)
    local cached = worldCache[npc]
    if cached ~= nil then return cached or nil end
    local ok, continent, world = pcall(MapToWorld, npc)
    local pos = ok and continent and world and { continent = continent, x = world.x, y = world.y } or false
    worldCache[npc] = pos
    return pos or nil
end

local function Here()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if not position then return nil end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, map, position)
    if not ok or not continent or not world then return nil end
    return { continent = continent, x = world.x, y = world.y }
end

local function Nearest(list)
    return Rules.NearestStop(list, T.side, Here(), WorldPos, IsCapital)
end

local function MapName(npc)
    local info = C_Map.GetMapInfo(npc[1])
    return info and info.name or nil
end

function Route.Narrow(data)
    if trainers then return end
    trainers, masters, capitals = {}, {}, data.capitals or {}
    for _, npc in ipairs(data.npcs or {}) do
        if Rules.ForFaction(npc, T.side) then
            if npc[6] == T.classToken then
                trainers[#trainers + 1] = npc
            elseif npc[6] == false then
                masters[#masters + 1] = npc
            end
        end
    end
end

-- Builds the list on the first plan that needs a stop. In combat the build
-- waits, and the module's DataReady comes back through Narrow.
function Route.Ensure()
    if trainers or Route.failed then return end
    T.module:LoadData(SOURCE)
end

function Route.Ready()
    return trainers ~= nil
end

-- The footer's text, and for a stop its map apart, so the panel can break the line
-- there. Nil: the list failed to load, and the footer says nothing.
function Route.Footer()
    if Route.failed then return nil end
    if not trainers then return TEXT_AFTER_COMBAT end
    local npc = Nearest(trainers)
    if not npc then return TEXT_NO_TRAINER end
    return "Nearest trainer: " .. npc[4], MapName(npc)
end

-- A weapon row's second line: who teaches it, and for a master the map apart.
function Route.WeaponText(weapon)
    if not weapon.masters then return TEXT_CLASS_TRAINER end
    if not masters then return TEXT_SOME_MASTER end
    local names, list = {}, {}
    for _, name in ipairs(weapon.masters) do names[name] = true end
    for _, npc in ipairs(masters) do
        if names[npc[4]] then list[#list + 1] = npc end
    end
    local npc = Nearest(list)
    if not npc then return TEXT_NO_MASTER end
    return "Weapon master: " .. npc[4], MapName(npc)
end
