-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Dungeons/CCTrackerRules.lua                     ║
-- ║  Purpose: CC Tracker's shipped crowd control list and    ║
-- ║           its pure rules. No WoW API, no frames.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ceil, floor, huge = math.ceil, math.floor, math.huge
local math_max, math_min = math.max, math.min
local ipairs, pairs, tonumber, type = ipairs, pairs, tonumber, type

local Rules = {}
KE.CCTrackerRules = Rules

Rules.NAME_GAP = 6
Rules.CC_PER_ROW = 3
Rules.ICON_GAP = 2

-- Debuff ids, which for several spells differ from the cast's id. `group` is
-- the row the settings page lists the spell under. Mind Control is left out:
-- the controlled mob turns assistable, and an assistable unit never gets a row.
KE.CC_TRACKER_SEEDS = {
    { key = "POLYMORPH", label = "Polymorph (all)", group = "Mage", default = true, ids = {
        118, 28272, 28271, 61305, 61721, 61780, 126819, 161353,
        161354, 161355, 161372, 277787, 277792, 321395, 391622, 383121,
    } },
    { key = "RING_OF_FROST", label = "Ring of Frost", group = "Mage", default = false, ids = { 82691 } },
    { key = "HEX", label = "Hex (all)", group = "Shaman", default = true, ids = {
        51514, 210873, 211004, 211010, 211015, 269352, 277778, 277784, 309328,
    } },
    { key = "REPENTANCE", label = "Repentance", group = "Paladin", default = true, ids = { 20066 } },
    { key = "TURN_EVIL", label = "Turn Evil", group = "Paladin", default = true, ids = { 10326 } },
    { key = "FREEZING_TRAP", label = "Freezing Trap", group = "Hunter", default = true, ids = { 3355 } },
    { key = "SCARE_BEAST", label = "Scare Beast", group = "Hunter", default = true, ids = { 1513 } },
    { key = "SAP", label = "Sap", group = "Rogue", default = true, ids = { 6770 } },
    { key = "BLIND", label = "Blind", group = "Rogue", default = true, ids = { 2094 } },
    { key = "BANISH", label = "Banish", group = "Warlock", default = true, ids = { 710 } },
    { key = "FEAR", label = "Fear", group = "Warlock", default = true, ids = { 118699 } },
    { key = "SEDUCTION", label = "Seduction", group = "Warlock", default = true, ids = { 6358 } },
    { key = "MESMERIZE", label = "Mesmerize", group = "Warlock", default = true, ids = { 115268 } },
    { key = "HIBERNATE", label = "Hibernate", group = "Druid", default = true, ids = { 2637 } },
    { key = "ENTANGLING_ROOTS", label = "Entangling Roots", group = "Druid", default = false, ids = { 339 } },
    { key = "IMPRISON", label = "Imprison", group = "Others", default = true, ids = { 217832 } },
    { key = "SLEEP_WALK", label = "Sleep Walk", group = "Others", default = true, ids = { 360806 } },
    { key = "PARALYSIS", label = "Paralysis", group = "Others", default = true, ids = { 115078 } },
    { key = "SHACKLE_HORROR", label = "Shackle Horror", group = "Others", default = true, ids = { 9484 } },
}

local MSG_NOT_ID = "Enter a whole positive number."
local MSG_NO_SPELL = "No spell with that id."
local MSG_ADDED = "Already added."

local function IsWholePositive(n)
    return type(n) == "number" and n > 0 and n < huge and n == floor(n)
end

-- A saved override counts only when its flag is a boolean; anything else
-- falls back to the shipped default.
function Rules.SeedEnabled(seed, groups)
    local override = type(groups) == "table" and groups[seed.key]
    if type(override) == "table" and type(override.enabled) == "boolean" then
        return override.enabled
    end
    return seed.default == true
end

function Rules.ResolveIDs(seeds, groups, customIDs)
    local ids, count = {}, 0
    for _, seed in ipairs(seeds) do
        if Rules.SeedEnabled(seed, groups) then
            for _, id in ipairs(seed.ids) do
                if not ids[id] then
                    ids[id] = true
                    count = count + 1
                end
            end
        end
    end
    if type(customIDs) == "table" then
        for id, on in pairs(customIDs) do
            if on == true and IsWholePositive(id) and not ids[id] then
                ids[id] = true
                count = count + 1
            end
        end
    end
    return ids, count
end

function Rules.FilterString(source, everyCC)
    local filter = "HARMFUL"
    if source == "MINE" then filter = filter .. "|PLAYER" end
    if everyCC then filter = filter .. "|CROWD_CONTROL" end
    return filter
end

function Rules.Candidates(everyCC, ids)
    if everyCC then return nil end
    return { includeSpellIDs = ids }
end

-- nil means the plate gets a slot. Only a plain false on the assist read
-- passes: on an assistable unit the game skips the spell-id filter and every
-- debuff would show. Any other unreadable read lets the unit through.
function Rules.Verdict(unit, api)
    if api.exists(unit) ~= true then return "no unit" end
    if api.canAttack(unit) == false then return "not attackable" end
    if api.canAssist(unit) ~= false then return "assistable, or unreadable" end
    if api.isDead(unit) == true then return "dead" end
    if api.isBoss(unit) == true then return "boss" end
    return nil
end

-- The largest stack that can draw: every row's icons, countdowns and name fall
-- inside it. A countdown is centered on its icon and not clipped, so text
-- wider or taller than the icon (textW, textH) pads the box on both sides and
-- the first row hangs that far inside the corner. A name taller than the icon
-- is clipped to its window, which runs from the icon's near edge to the
-- container's far edge (the row spacing and 1 px past the icon), so the last
-- row's name can reach that far past the stack's far end.
-- No taller than MaxHeight, the screen's height: a clamp moves a frame and
-- cannot shrink it, so a taller box could not be kept on screen.
function Rules.StackBox(db, textW, textH)
    local size = db.IconSize or 40
    local spacing = db.RowSpacing or 2
    local cap = db.MaxEnemies or 15
    local padX = math_max(0, ceil(((textW or 0) - size) / 2))
    local padY = math_max(0, ceil(((textH or 0) - size) / 2))
    local icons = Rules.CC_PER_ROW * size + (Rules.CC_PER_ROW - 1) * Rules.ICON_GAP
    local width = 2 * padX + icons
    local nameFar = 0
    if db.NameEnabled ~= false then
        width = width + Rules.NAME_GAP + (db.NameWidth or 150)
        local over = ceil(((db.NameFontSize or 14) - size) / 2)
        nameFar = math_max(0, math_min(spacing + 1, over) - padY)
    end
    local up = db.GrowDirection == "UP"
    local pos = db.Position
    local from = type(pos) == "table" and pos.AnchorFrom
    if type(from) ~= "string" then from = "" end
    local side = from:find("LEFT") and "LEFT" or (from:find("RIGHT") and "RIGHT" or "")
    local height = cap * size + (cap - 1) * spacing + 2 * padY + nameFar
    local maxHeight = db.MaxHeight
    if type(maxHeight) == "number" and maxHeight > 0 then height = math_min(height, maxHeight) end
    return {
        width = width,
        height = height,
        insetX = padX,
        insetY = padY,
        corner = up and "BOTTOMLEFT" or "TOPLEFT",
        selfPoint = (up and "BOTTOM" or "TOP") .. side,
    }
end

-- The preview's stand-in for the live formatter: whole seconds, or tenths
-- below the Show Decimals Below threshold (already normalized by the caller).
function Rules.SampleTime(seconds, threshold)
    if threshold > 0 and seconds < threshold then
        return ("%.1f"):format(seconds)
    end
    return ("%d"):format(seconds)
end

function Rules.CanAdd(text, seeds, customIDs, getName)
    local id = tonumber(text)
    if not IsWholePositive(id) then return nil, MSG_NOT_ID end
    if not getName(id) then return nil, MSG_NO_SPELL end
    for _, seed in ipairs(seeds) do
        for _, seedID in ipairs(seed.ids) do
            if seedID == id then return nil, "Already tracked as " .. seed.label .. "." end
        end
    end
    if type(customIDs) == "table" and customIDs[id] then return nil, MSG_ADDED end
    return id
end
