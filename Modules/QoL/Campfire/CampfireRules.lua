-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/QoL/Campfire/CampfireRules.lua                  ║
-- ║  Purpose: Campfire's camp ids, its bonus table, and its  ║
-- ║           pure rules. No WoW API, no frames.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local abs, ceil, floor = math.abs, math.ceil, math.floor
local format = string.format
local ipairs, pairs, tonumber, unpack = ipairs, pairs, tonumber, unpack

local Rules = {}
KE.CampfireRules = Rules

Rules.CAMP_BENEFITS = 1229741
Rules.IN_RANGE = 1283391
Rules.SEATED = { 1229739, 1289723 }
Rules.WELL_RESTED = 429959
Rules.WELL_RESTED_STACKS = 3
Rules.SLEEPING_BAG = 211527
Rules.KITS = { 279974, 279961, 279981 }

Rules.MIN_SIT_GAIN = 600
-- True once sitting again is proven to refill the buff to its full duration.
Rules.REFILL_PROVEN = false

local COLOR_GOOD_ABOVE, COLOR_WARN_ABOVE = 1800, 300
local EXPIRY_SLACK = 1

-- points: how many numbers aura.points carries, default 1. numbers: how many
-- the amount text takes, default points. period: the fixed second number of a
-- per-period bonus.
Rules.FEATURES = {
    { id = 1229451, short = "Rested", name = "Camp Tent", stat = "Rested experience", points = 0,
        aliases = { "Tent", "Camp Tent", "Tanning Rack", "Sewing Machine" } },
    { id = 1230172, short = "Str", name = "Sharpening Wheel", stat = "Strength", amount = "+%s Strength",
        aliases = { "Sharpening Wheel", "Anvil", "Master Forge" } },
    { id = 1230124, short = "Sta", name = "First Aid Kit", stat = "Stamina", amount = "+%s Stamina",
        aliases = { "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory" } },
    { id = 1229513, short = "Int", name = "Incense Candle", stat = "Intellect", amount = "+%s Intellect",
        aliases = { "Incense Candle", "Greenhouse", "Seed Hybridizer" } },
    { id = 1229718, short = "Spi", name = "Faction Banner", stat = "Spirit", amount = "+%s Spirit",
        aliases = { "Faction Banner", "Spinning Wheel", "Loom" } },
    { id = 1230098, short = "Stats", unit = "%", name = "Fish Bowl", stat = "All stats", amount = "+%s%% all stats",
        aliases = { "Fish Bowl", "Fishing Rack", "Fishing Hut" } },
    { id = 1230653, short = "Armor", name = "Enchanted Lute", stat = "Armor, all stats and resistances",
        amount = "+%s Armor, +%s all stats, +%s resistances", points = 3, aliases = { "Enchanted Lute" } },
    { id = 1230164, short = "AP", name = "Lodestone", stat = "Melee Attack Power", amount = "+%s Melee Attack Power",
        aliases = { "Lodestone", "Rock Garden", "Molten Foundry" } },
    { id = 1230552, short = "SP", stat = "Spell damage and healing", amount = "+%s spell damage, +%s healing",
        points = 2 },
    { id = 1229519, short = "Crit", unit = "%", name = "Camp Chair", stat = "Critical Strike",
        amount = "+%s%% Critical Strike", aliases = { "Camp Chair", "Trapper's Workbench", "Field Guide" } },
    { id = 1230587, short = "MP5", name = "Mana Well", stat = "Mana every 5 sec", amount = "+%s Mana every %s sec",
        numbers = 2, period = 5, aliases = { "Mana Well", "Fermenter", "Alchemy Laboratory" } },
    { id = 1283701, short = "Disenchant", name = "Arcane Salvager", stat = "Better disenchanting", points = 0 },
}

-- A camp bonus does not stack with the class buff it replaces. One name read
-- per base id, so no rank table is needed.
Rules.COVERED_BY = {
    [1230587] = { 19742, 25894 },
    [1230172] = { 8075, 8076 },
    [1230653] = { 1126, 21849 },
    [1230124] = { 1243, 21562 },
    [1230098] = { 20217, 25898 },
    [1229513] = { 1459, 23028 },
    [1229718] = { 14752, 27681 },
    [1229519] = { 24907 },
    [1230164] = { 19740, 25782 },
}

Rules.COVER_IDS = {}
for _, ids in pairs(Rules.COVERED_BY) do
    for _, id in ipairs(ids) do Rules.COVER_IDS[#Rules.COVER_IDS + 1] = id end
end

local FEATURE_BY_ID = {}
for _, feature in ipairs(Rules.FEATURES) do FEATURE_BY_ID[feature.id] = feature end

-- Checked in order, so "armor, all stats" reads as the armor row.
local EFFECT_WORDS = {
    { "rested", 1229451 }, { "rest experience", 1229451 }, { "disenchant", 1283701 },
    { "critical strike", 1229519 }, { "spell damage", 1230552 }, { "spell power", 1230552 },
    { "armor", 1230653 }, { "attack power", 1230164 }, { "strength", 1230172 }, { "stamina", 1230124 },
    { "intellect", 1229513 }, { "spirit", 1229718 }, { "mana", 1230587 }, { "mp5", 1230587 },
    { "stats", 1230098 },
}

local LINE = "^%s*(.-)%s*:%s*(%S.-)%s*$"
local WIDE_LINE = "^%s*(.-)%s*\239\188\154%s*(%S.-)%s*$"
local NUMBER = "(%d+)([%.,]?)(%d*)"

---------------------------------------------------------------------------------
-- The moment
---------------------------------------------------------------------------------

function Rules.TimerHiddenInCombat(inCombat, settings)
    return inCombat and not settings.TimerInCombat or false
end

function Rules.SitClickable(near, settings, inCombat)
    return (near and settings.ClickToSit and not inCombat) and true or false
end

function Rules.SitGain(left, duration)
    return duration - left
end

function Rules.SitGainReachedIn(left, duration, refillProven)
    if not refillProven then return nil end
    local gain = Rules.SitGain(left, duration)
    if gain >= Rules.MIN_SIT_GAIN then return nil end
    return Rules.MIN_SIT_GAIN - gain
end

local function PreviewAlert(i)
    local settings = i.settings
    if not settings.AlertEnabled then return false end
    return i.preview == "Passing" or (i.preview == "FireHere" and settings.Shape == "ROUND")
end

-- Returns the moment, whether the shape shows, whether the alert shows, and
-- the effective fire near. Moments: Nothing, Held, Sitting, Landing, Passing,
-- Spare, Low, Shown, Road, FireHere, NoCamp. A preview returns its own id.
function Rules.SelectMoment(i)
    local s = i.settings
    if i.preview then return i.preview, true, PreviewAlert(i), false end
    if i.inInstance then return "Nothing", false, false, false end
    if Rules.TimerHiddenInCombat(i.inCombat, s) then return "Nothing", false, false, false end
    if i.held then return "Held", false, false, false end

    local near = (i.inRange and not i.dead and not i.onTaxi) and true or false
    if i.seated then return "Sitting", true, false, near end

    if i.buffUp then
        if i.landing then return "Landing", true, false, near end
        local alertUnder = s.AlertUnderMinutes * 60
        local underAlert = i.left <= alertUnder
        if near and (underAlert or i.offersNew) then
            local alert = (s.AlertEnabled and not i.dismissed and not i.inCombat) and true or false
            return "Passing", true, alert, near
        end
        if near and i.refillProven and Rules.SitGain(i.left, i.duration) >= Rules.MIN_SIT_GAIN then
            return "Spare", true, false, near
        end
        local timerAllowed = near or not ((i.inRest and not s.TimerInRestAreas)
            or (i.mounted and not s.TimerWhileMounted))
        if timerAllowed and i.left <= s.ShowUnderMinutes * 60 then return "Low", true, false, near end
        if timerAllowed and s.ShowAlways then return "Shown", true, false, near end
        return "Road", false, false, near
    end

    if i.inCombat then return "Nothing", false, false, near end
    if near then
        local alert = (s.AlertEnabled and not i.dismissed and s.Shape == "ROUND") and true or false
        return "FireHere", true, alert, near
    end
    if i.dead or i.onTaxi then return "Nothing", false, false, near end
    if i.inRest and not s.GrayInRestAreas then return "Nothing", false, false, near end
    if i.mounted and not s.GrayWhileMounted then return "Nothing", false, false, near end
    if not s.ShowMissing then return "Nothing", false, false, near end
    return "NoCamp", true, false, near
end

function Rules.RingColorKey(left, seated)
    if seated then return "seated" end
    if left > COLOR_GOOD_ABOVE then return "good" end
    if left > COLOR_WARN_ABOVE then return "warn" end
    return "bad"
end

function Rules.NextColorStepIn(left)
    if left > COLOR_GOOD_ABOVE then return left - COLOR_GOOD_ABOVE end
    if left > COLOR_WARN_ABOVE then return left - COLOR_WARN_ABOVE end
    return nil
end

-- One aura's expiry may move by a rounding error between two reads. Every later
-- comparison sees the earlier read until the expiry really moves, so the timers,
-- the landing and the views all agree without a slack of their own.
function Rules.SteadyExpiry(previous, expiry)
    if previous and expiry and abs(expiry - previous) <= EXPIRY_SLACK then return previous end
    return expiry
end

-- prev.seated means the player has sat since the last landing: the seated aura
-- and the buff change in separate events, in either order.
function Rules.IsLanding(prev, now)
    if not prev.seated or not now.expiry then return false end
    return not prev.expiry or now.expiry > prev.expiry
end

-- The window runs from the landing, whatever happened to its animation since.
function Rules.LandingActive(landingEnds, now)
    return (landingEnds and now < landingEnds) and true or false
end

---------------------------------------------------------------------------------
-- Bonuses
---------------------------------------------------------------------------------

function Rules.NameIndex(features, spellNameOf)
    local index = {}
    for _, feature in ipairs(features) do
        for _, alias in ipairs(feature.aliases or {}) do index[alias:lower()] = feature end
        local localized = spellNameOf and spellNameOf(feature.id)
        if localized then index[localized:lower()] = feature end
    end
    return index
end

local function ReadNumbers(effect)
    local out = {}
    for whole, mark, part in effect:gmatch(NUMBER) do
        if mark ~= "" and #part == 3 then
            out[#out + 1] = tonumber(whole .. part)
        elseif mark ~= "" and part ~= "" then
            out[#out + 1] = tonumber(whole .. "." .. part)
        else
            out[#out + 1] = tonumber(whole)
        end
    end
    return out
end

local function FeatureByEffect(effect)
    for _, entry in ipairs(EFFECT_WORDS) do
        if effect:find(entry[1], 1, true) then return FEATURE_BY_ID[entry[2]] end
    end
    return nil
end

function Rules.ParseBonusLine(text, nameIndex)
    local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local label, effect = clean:match(LINE)
    if not label then label, effect = clean:match(WIDE_LINE) end
    if not label or label == "" or label:find("[%d|]") or label:find("ID$") then return nil end
    local feature = nameIndex[label:lower()] or FeatureByEffect(effect:lower())
    if not feature then return nil end
    local amounts = ReadNumbers(effect)
    local period = feature.period
    if period and amounts[1] == period and amounts[2] and amounts[2] ~= period then
        amounts[1], amounts[2] = amounts[2], amounts[1]
    end
    return feature, amounts
end

function Rules.MergeBonuses(features, auraPoints, tipLines)
    local fromTip = {}
    for _, line in ipairs(tipLines) do
        local id = line.feature.id
        if not fromTip[id] then fromTip[id] = line.amounts end
    end
    local rows = {}
    for _, feature in ipairs(features) do
        local aura, tip = auraPoints[feature.id], fromTip[feature.id]
        if aura or tip then
            local amounts = (aura and aura[1]) and aura or tip or aura
            rows[#rows + 1] = { id = feature.id, feature = feature, amounts = amounts }
        end
    end
    return rows
end

local function NumberText(value)
    if value == floor(value) then return format("%d", value) end
    return format("%.1f", value)
end

-- Returns the label, then its amount and name apart so a view can color them.
function Rules.Label(feature, amount)
    if feature.points == 0 or not amount then return feature.short, nil, feature.short end
    local head = "+" .. NumberText(amount) .. (feature.unit or "")
    return head .. " " .. feature.short, head, feature.short
end

function Rules.Words(feature, amounts)
    if not feature.amount then return feature.stat end
    local count = feature.numbers or feature.points or 1
    local texts = {}
    for n = 1, count do
        local value = amounts[n] or (n == count and feature.period)
        if not value then return feature.stat end
        texts[n] = NumberText(value)
    end
    return format(feature.amount, unpack(texts, 1, count))
end

-- A row is new if its feature is not held or its first amount is higher. A
-- held row not read at all is kept, since resting again keeps old effects.
function Rules.NewBonuses(held, now)
    local heldById = {}
    for _, row in ipairs(held) do heldById[row.id] = row end
    local newRows, keptRows, seen = {}, {}, {}
    for _, row in ipairs(now) do
        seen[row.id] = true
        local old = heldById[row.id]
        local amount, oldAmount = row.amounts[1], old and old.amounts[1]
        if not old or (amount and oldAmount and amount > oldAmount) then
            newRows[#newRows + 1] = row
        else
            keptRows[#keptRows + 1] = row
        end
    end
    for _, row in ipairs(held) do
        if not seen[row.id] then keptRows[#keptRows + 1] = row end
    end
    return newRows, keptRows
end

function Rules.Coverer(featureId, onYou)
    local ids = Rules.COVERED_BY[featureId]
    if not ids then return nil end
    for _, id in ipairs(ids) do
        if onYou[id] then return onYou[id] end
    end
    return nil
end

local function LineRank(row)
    if row.coverer then return 3 end
    if row.isNew then return 1 end
    return 2
end

function Rules.OrderLines(rows)
    local out = {}
    for rank = 1, 3 do
        for _, row in ipairs(rows) do
            if LineRank(row) == rank then out[#out + 1] = row end
        end
    end
    return out
end

-- A covered new row does not count right now, so it offers nothing and takes
-- the dim look. With dimming off, nothing is treated as covered.
function Rules.FreshRows(newRows, dim, onYou)
    local fresh = {}
    for _, row in ipairs(newRows) do
        if not (dim and Rules.Coverer(row.id, onYou)) then fresh[#fresh + 1] = row end
    end
    return fresh
end

function Rules.BuildLines(newRows, keptRows, dim, onYou, keptStyle)
    local lines = {}
    for _, row in ipairs(newRows) do
        local coverer = dim and Rules.Coverer(row.id, onYou) or nil
        lines[#lines + 1] = { row = row, isNew = true, coverer = coverer, style = coverer and "dim" or "new" }
    end
    for _, row in ipairs(keptRows) do
        local coverer = dim and Rules.Coverer(row.id, onYou) or nil
        lines[#lines + 1] = { row = row, coverer = coverer, style = coverer and "dim" or keptStyle }
    end
    return Rules.OrderLines(lines)
end

function Rules.HasFreshLine(lines)
    for _, line in ipairs(lines) do
        if line.isNew and not line.coverer then return true end
    end
    return false
end

-- Returns the text, the minutes left, and the minutes added or nil.
function Rules.AlertLine(left, duration, refillProven)
    local minutes = ceil(left / 60)
    local added = floor(duration / 60 + 0.5) - minutes
    if refillProven and added > 0 then
        return format("%dm left, sit for +%dm", minutes, added), minutes, added
    end
    return format("%dm left", minutes), minutes, nil
end

-- Stays the same number for every read within one minute of the text, so it
-- also names which minute a one-shot was armed for.
function Rules.AlertMinuteEnd(expiry, left)
    return expiry - (ceil(left / 60) - 1) * 60
end

---------------------------------------------------------------------------------
-- Checklist and buttons
---------------------------------------------------------------------------------

function Rules.DotState(present, stacks, maxStacks)
    if not present then return "off" end
    if maxStacks and stacks and stacks < maxStacks then return "part" end
    return "on"
end

function Rules.BestKit(kits, countOf, usableOf)
    for _, id in ipairs(kits) do
        if countOf(id) > 0 and usableOf(id) then return id end
    end
    return nil
end

-- What the moment and settings allow, before any inventory read.
function Rules.ButtonCandidate(moment, nearOrSeated, combat, settings)
    if combat then return nil end
    if nearOrSeated then return settings.BagButton and "bag" or nil end
    if moment == "NoCamp" and settings.KitButton then return "kit" end
    return nil
end

function Rules.ButtonWanted(moment, nearOrSeated, combat, settings, carried)
    local candidate = Rules.ButtonCandidate(moment, nearOrSeated, combat, settings)
    if candidate and carried[candidate] then return candidate end
    return nil
end
