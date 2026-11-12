-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrainingRules.lua                                       ║
-- ║  Purpose: What's Training's pure rules: service reads,   ║
-- ║           spell states, prices, the plan, the buy and    ║
-- ║           the rank swap. No WoW API.                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Rules = {}
KE.TrainingRules = Rules

local floor, max, min = math.floor, math.max, math.min
local ipairs, pairs, select, tonumber, type = ipairs, pairs, select, tonumber, type
local concat, sort = table.concat, table.sort

local SOON = 2
local MAX_LEVEL = 60
local MILESTONES = { 40, 50, 60 }
local KINDS = { available = true, unavailable = true, used = true, header = true }
local NUMBER = "%d+%.?%d*"
local TAG_QUEST = "Quest or trainer"
local TAG_TALENT = "May need a talent"
local NONE = {}

-- A number followed by one of these is a duration or a reach, never a rank's gain.
local UNITS = {
    sec = true, secs = true, second = true, seconds = true, min = true, mins = true, minute = true,
    minutes = true, hour = true, hours = true, hr = true, hrs = true, yard = true, yards = true,
    yd = true, yds = true,
}

-- Words that end a rank gain's label rather than describe what grew.
local STOP = {
    over = true, ["for"] = true, to = true, ["and"] = true, by = true, ["in"] = true, of = true,
    the = true, a = true, an = true, every = true, per = true, with = true, at = true, on = true,
    your = true, you = true, target = true, increases = true, increase = true, reduces = true,
    reduce = true, deals = true, causes = true, restores = true, heals = true, adds = true,
}

---------------------------------------------------------------------------------
-- Data load
---------------------------------------------------------------------------------
function Rules.BuildStep(built, inCombat)
    if built then return "have" end
    if inCombat then return "wait" end
    return "build"
end

-- A source that builds can still hold a field no later rule can read, an optional
-- one included, so these accept exactly what the generator writes.
local function ListOf(list, kind)
    if type(list) ~= "table" then return false end
    for _, value in ipairs(list) do
        if type(value) ~= kind then return false end
    end
    return true
end

local function AllRows(rows, isValid)
    if type(rows) ~= "table" then return false end
    for _, row in ipairs(rows) do
        if not isValid(row) then return false end
    end
    return true
end

local function SpellRowValid(row)
    if type(row) ~= "table" or type(row[1]) ~= "number" or type(row[2]) ~= "number" or type(row[3]) ~= "number" then
        return false
    end
    if row.needs ~= nil and type(row.needs) ~= "number" then return false end
    if row.races ~= nil and not ListOf(row.races, "number") then return false end
    if row.quest ~= nil and row.quest ~= true and row.quest ~= "maybe" then return false end
    return row.talent == nil or type(row.talent) == "number" or row.talent == "maybe"
end

local function WeaponRowValid(row)
    if type(row) ~= "table" or type(row[1]) ~= "number" or type(row[2]) ~= "number" then return false end
    return row.masters == nil or ListOf(row.masters, "string")
end

local function NpcValid(npc)
    if type(npc) ~= "table" or type(npc[1]) ~= "number" or type(npc[2]) ~= "number" or type(npc[3]) ~= "number" then
        return false
    end
    if type(npc[4]) ~= "string" or type(npc[5]) ~= "string" or type(npc[7]) ~= "string" then return false end
    return npc[6] == false or type(npc[6]) == "string"
end

-- replaced maps a spell id to the ids the client says replace it.
local function ReplacedValid(replaced)
    if replaced == nil then return true end
    if type(replaced) ~= "table" then return false end
    for id, list in pairs(replaced) do
        if type(id) ~= "number" or not ListOf(list, "number") or #list == 0 then return false end
    end
    return true
end

function Rules.ClassDataValid(data)
    return type(data) == "table" and AllRows(data.spells, SpellRowValid) and AllRows(data.weapons, WeaponRowValid)
        and ReplacedValid(data.replaced)
end

function Rules.RouteDataValid(data)
    return type(data) == "table" and type(data.capitals) == "table" and AllRows(data.npcs, NpcValid)
end

---------------------------------------------------------------------------------
-- Trainer services
---------------------------------------------------------------------------------
-- Finds the kind and icon by what they are, so it holds for either value order. The
-- fifth value is the rank text the window shows beside the name, such as "Rank 2".
function Rules.ReadService(...)
    local kind, icon
    for i = 2, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" then
            if not kind and KINDS[value] then kind = value end
        elseif type(value) == "number" then
            if not icon and value > 1000 then icon = value end
        end
    end
    local level, rank = select(4, ...)
    if type(rank) ~= "string" or rank == "" or KINDS[rank] then rank = nil end
    return (...), kind, icon, type(level) == "number" and level or nil, rank
end

function Rules.ServiceOpen(kind, level, playerLevel, isKnown)
    if kind == "available" then return true end
    if kind then return false end
    if not level or level == 0 then return false end
    return level <= playerLevel and not isKnown
end

function Rules.ServiceKey(name, level)
    return name .. "|" .. (level or 0)
end

function Rules.SpellsByKey(rows, nameOf)
    local byKey = {}
    for _, row in ipairs(rows) do
        local name = nameOf(row[2])
        if name then
            local key = Rules.ServiceKey(name, row[1])
            if not byKey[key] then byKey[key] = row end
        end
    end
    return byKey
end

-- Only a price the trainer window would show is a read: it shows no money for a
-- known service or a cost of 0.
function Rules.ReadPrices(services, byKey, prices)
    local changed = false
    for _, service in ipairs(services) do
        local row = service.name and byKey[Rules.ServiceKey(service.name, service.level)]
        if row and service.kind ~= "used" and service.cost and service.cost > 0
            and prices[row[2]] ~= service.cost then
            prices[row[2]] = service.cost
            changed = true
        end
    end
    return changed
end

---------------------------------------------------------------------------------
-- Filters and states
---------------------------------------------------------------------------------
function Rules.ForRace(row, race)
    if not row.races then return true end
    for _, id in ipairs(row.races) do
        if id == race then return true end
    end
    return false
end

function Rules.ForFaction(npc, side)
    if not side then return true end
    return npc[7]:find(side, 1, true) ~= nil
end

-- A spell the client replaces with another leaves the book once the other is
-- learned, so knowing any spell that replaces it counts.
function Rules.Known(id, isKnown, replaced)
    if isKnown(id) then return true end
    for _, other in ipairs(replaced and replaced[id] or NONE) do
        if isKnown(other) then return true end
    end
    return false
end

function Rules.KnownMap(rows, isKnown)
    local byId = {}
    for _, row in ipairs(rows) do byId[row[2]] = row end
    local known = {}
    for _, row in ipairs(rows) do
        if isKnown(row[2]) then
            local step = row
            while step and not known[step[2]] do
                known[step[2]] = true
                step = step.needs and byId[step.needs]
            end
        end
    end
    return known
end

function Rules.State(row, level, known, skipped, isKnown, prices)
    local id = row[2]
    if known[id] then return "known" end
    if skipped[id] then return "skipped" end
    if row.quest == true and not (prices and prices[id]) then return "quest" end
    if type(row.talent) == "number" and not isKnown(row.talent) then return "talent" end
    if row[1] > level + SOON then return "later" end
    if row[1] > level then return "soon" end
    if row.needs and not known[row.needs] and not isKnown(row.needs) then return "rank" end
    return "now"
end

function Rules.Tag(row)
    if row.quest == "maybe" then return TAG_QUEST end
    if row.talent == "maybe" then return TAG_TALENT end
    return nil
end

---------------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------------
function Rules.LevelPrices(rows, prices)
    local levels = {}
    for _, row in ipairs(rows) do
        local read = prices[row[2]]
        if read and not row.races and not row.talent and not levels[row[1]] then
            levels[row[1]] = read
        end
    end
    return levels
end

-- A race or talent row is priced apart from its level, and a seed of 0 means
-- the shipped table has no price at all, so none of them takes an inferred one.
function Rules.Price(row, prices, levelPrice)
    local read = prices[row[2]]
    if read then return read, "read" end
    if row.quest == true then return 0, "quest" end
    local cost = row[3] or 0
    if cost == 0 then return 0, "none" end
    local inferred = not row.races and not row.talent and levelPrice[row[1]]
    if inferred then return inferred, "~" end
    return cost, "~"
end

function Rules.Sum(rows, priceOf)
    local total, approx, unpriced = 0, false, 0
    for _, row in ipairs(rows) do
        local copper, mark = priceOf(row)
        if mark == "none" then
            unpriced = unpriced + 1
        elseif mark ~= "quest" then
            total = total + copper
            if mark == "~" then approx = true end
        end
    end
    return total, approx, unpriced
end

local function NewSection()
    return { rows = {}, copper = 0, approx = false, unpriced = 0 }
end

local function AddEntry(section, entry)
    section.rows[#section.rows + 1] = entry
    if entry.mark == "none" then
        section.unpriced = section.unpriced + 1
    elseif entry.mark ~= "quest" then
        section.copper = section.copper + entry.copper
        if entry.mark == "~" then section.approx = true end
    end
end

---------------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------------
function Rules.Plan(rows, ctx)
    local isKnown, prices, skipped = ctx.isKnown, ctx.prices, ctx.skipped
    local known = Rules.KnownMap(rows, isKnown)
    local levelPrice = Rules.LevelPrices(rows, prices)
    local nameOf = ctx.nameOf

    local plan = {
        level = ctx.level, gold = ctx.gold, rows = {}, entry = {}, priced = {}, leveled = {},
        now = NewSection(), rank = NewSection(), quest = NewSection(), soon = NewSection(),
        talent = NewSection(), skipped = NewSection(), known = NewSection(), later = {}, weapons = {},
    }

    local laterByLevel = {}
    for _, row in ipairs(rows) do
        local id = row[2]
        if Rules.ForRace(row, ctx.race) and (not nameOf or nameOf(id)) then
            local state = Rules.State(row, ctx.level, known, skipped, isKnown, prices)
            local copper, mark = Rules.Price(row, prices, levelPrice)
            local entry = {
                row = row, id = id, level = row[1], copper = copper, mark = mark,
                state = state, tag = Rules.Tag(row),
            }
            plan.rows[#plan.rows + 1] = row
            plan.entry[id] = entry
            if row.quest ~= true and state ~= "talent" and state ~= "known" then
                plan.priced[#plan.priced + 1] = row
            end
            if state == "later" then
                local group = laterByLevel[row[1]]
                if not group then
                    group = NewSection()
                    group.level = row[1]
                    laterByLevel[row[1]] = group
                    plan.later[#plan.later + 1] = group
                end
                AddEntry(group, entry)
            else
                AddEntry(plan[state], entry)
            end
        end
    end
    sort(plan.later, function(a, b) return a.level < b.level end)

    local running, runningApprox, runningUnpriced, gold = 0, false, 0, ctx.gold or 0
    local function Pass(ref, copper, approx, unpriced)
        running = running + copper
        runningApprox = runningApprox or approx
        runningUnpriced = runningUnpriced + unpriced
        if not plan.goldAt and running > gold then plan.goldAt = ref end
    end
    for _, section in ipairs({ plan.now, plan.rank, plan.soon }) do
        for _, entry in ipairs(section.rows) do
            plan.leveled[#plan.leveled + 1] = entry
            Pass(entry, entry.copper, entry.mark == "~", entry.mark == "none" and 1 or 0)
        end
    end
    plan.neededBy = running
    plan.neededApprox = runningApprox
    plan.neededUnpriced = runningUnpriced
    plan.neededLevel = min(ctx.level + SOON, MAX_LEVEL)
    for _, group in ipairs(plan.later) do
        for _, entry in ipairs(group.rows) do
            plan.leveled[#plan.leveled + 1] = entry
        end
        Pass(group, group.copper, group.approx, group.unpriced)
        group.byThen = running
        group.byThenApprox = runningApprox
        group.byThenUnpriced = runningUnpriced
    end

    for _, weapon in ipairs(ctx.weapons or {}) do
        if weapon[1] <= ctx.level and not isKnown(weapon[2]) and (not nameOf or nameOf(weapon[2])) then
            plan.weapons[#plan.weapons + 1] = weapon
        end
    end
    return plan
end

function Rules.Milestones(plan, level)
    local stops = {}
    for _, target in ipairs(MILESTONES) do
        if target >= level then
            local copper, approx, unpriced = 0, false, 0
            for _, entry in ipairs(plan.leveled) do
                if entry.level <= target then
                    copper = copper + entry.copper
                    if entry.mark == "~" then approx = true end
                    if entry.mark == "none" then unpriced = unpriced + 1 end
                end
            end
            stops[#stops + 1] = { level = target, copper = copper, approx = approx, unpriced = unpriced }
        end
    end
    return stops
end

-- Where the running priced total first passes the gold. A row at or below the level
-- counts at the level, and a row of TRAIN NOW is this visit. Nil when the gold covers
-- every priced spell.
function Rules.GoldEnd(plan)
    local at = plan.goldAt
    if not at then return nil end
    return max(at.level, plan.level), at.state == "now"
end

-- The stops in order, with a line carrying the gold's end before the first stop at or
-- past it.
function Rules.Ladder(stops, endLevel)
    local lines, placed = {}, false
    for _, stop in ipairs(stops) do
        if endLevel and not placed and stop.level >= endLevel then
            lines[#lines + 1] = { goldEnd = endLevel }
            placed = true
        end
        lines[#lines + 1] = stop
    end
    return lines
end

function Rules.ReadCount(rows, prices)
    local read = 0
    for _, row in ipairs(rows) do
        if prices[row[2]] then read = read + 1 end
    end
    return read, #rows
end

function Rules.Search(rows, query, nameOf)
    local found, needle = {}, query:lower()
    for _, row in ipairs(rows) do
        local name = nameOf(row[2])
        if name and name:lower():find(needle, 1, true) then found[#found + 1] = row end
    end
    return found
end

function Rules.SkipAll(rows, name, nameOf, skipped, value)
    for _, row in ipairs(rows) do
        if nameOf(row[2]) == name then skipped[row[2]] = value end
    end
end

---------------------------------------------------------------------------------
-- Rank gain
---------------------------------------------------------------------------------
local function Numbers(text)
    local found = {}
    for first, value, last in text:gmatch("()(" .. NUMBER .. ")()") do
        found[#found + 1] = {
            value = tonumber(value), first = first, last = last, endsSentence = value:sub(-1) == ".",
        }
    end
    return found
end

-- The number whose following words describe this one: past "N to M" in a range.
local function TailOf(text, numbers, i)
    local item, following = numbers[i], numbers[i + 1]
    if following and text:sub(item.last, following.first - 1) == " to " then return following end
    return item
end

local function IsTimeOrDistance(text, tail)
    local word = text:match("^%s*(%a+)", tail.last)
    return word ~= nil and UNITS[word:lower()] == true
end

local function WordsAfter(text, tail)
    local words = {}
    if tail.endsSentence then return words end
    local rest = text:match("^%%?([^%.,;:%d%(]*)", tail.last) or ""
    for word in rest:gmatch("%a+") do
        if STOP[word:lower()] or #words == 2 then break end
        words[#words + 1] = word
    end
    return words
end

local function WordsBefore(text, item)
    local head = text:sub(1, item.first - 1):match("([^%.,;:]*)$") or ""
    local all = {}
    for word in head:gmatch("%a+") do all[#all + 1] = word end
    local words = {}
    for i = #all, 1, -1 do
        if STOP[all[i]:lower()] then
            if #words > 0 then break end
        else
            table.insert(words, 1, all[i])
            if #words == 2 then break end
        end
    end
    return words
end

local function GainLabel(text, numbers, i, gain)
    local item = numbers[i]
    local tail = TailOf(text, numbers, i)
    local amount = "+" .. ("%.10g"):format(gain)
    if text:sub(tail.last, tail.last) == "%" then amount = amount .. "%" end
    local words = WordsAfter(text, tail)
    if #words == 0 and amount:sub(-1) ~= "%" then words = WordsBefore(text, item) end
    if #words == 0 then return amount end
    return amount .. " " .. concat(words, " ")
end

-- Joins digit groups, so "1,000" reads as one number and not as 1 and 0.
local function PlainDigits(text)
    local count
    repeat
        text, count = text:gsub("(%d),(%d%d%d)", "%1%2")
    until count == 0
    return text
end

function Rules.RankGain(oldText, newText)
    if type(oldText) ~= "string" or type(newText) ~= "string" then return nil end
    oldText, newText = PlainDigits(oldText), PlainDigits(newText)
    if (oldText:gsub(NUMBER, "#")) ~= (newText:gsub(NUMBER, "#")) then return nil end
    local old, new = Numbers(oldText), Numbers(newText)
    for i, item in ipairs(new) do
        if item.value > old[i].value and not IsTimeOrDistance(newText, TailOf(newText, new, i)) then
            return GainLabel(newText, new, i, item.value - old[i].value)
        end
    end
    return nil
end

---------------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------------
function Rules.PanelSide(roomL, roomR, need)
    if roomR >= need then return "right" end
    if roomL >= need then return "left" end
    if roomR >= roomL - 1 then return "pinRight" end
    return "pinLeft"
end

-- Closed, the panel stays hidden, whatever else could host it.
function Rules.PanelHost(s)
    if s.closed then return nil end
    if s.atTrainer and not s.gamepad and s.trainerWindow then return "trainer" end
    if s.bookOpen and not s.gamepad and s.openWithBook then return "book" end
    if s.alone then return "alone" end
    return nil
end

-- A closing holds only while a trainer visit or the book window lasts.
function Rules.StaysClosed(closed, atTrainer, bookWindow)
    return closed == true and (atTrainer == true or bookWindow == true)
end

-- What a trainer's closing leaves: whether the panel stays closed for a book window
-- left open, and whether it stays open alone to show the bar line.
function Rules.AfterTrainer(closed, staysOpen, bookWindow)
    return Rules.StaysClosed(closed, false, bookWindow), closed ~= true and staysOpen == true
end

-- A click on the Training button shows a hidden panel with the setting on, and otherwise
-- toggles the setting.
function Rules.BookButtonSetting(shown, openWithBook)
    if not shown then return true end
    return not openWithBook
end

-- In combat a panel on the book keeps that anchor, wherever it is wanted next.
-- A panel wanted on the book and not yet on it sits alone.
function Rules.PlaceStep(host, inCombat, onBook)
    if not inCombat then return "place" end
    if onBook then return "keep" end
    if host == "book" then return "alone" end
    return "place"
end

---------------------------------------------------------------------------------
-- Learn
---------------------------------------------------------------------------------
function Rules.Offers(services, ctx)
    local open, waiting = {}, {}
    for _, service in ipairs(services) do
        local kind, level = service.kind, service.level or 0
        if service.name and kind ~= "header" and kind ~= "used" then
            local key = Rules.ServiceKey(service.name, level)
            local row = ctx.byKey and ctx.byKey[key]
            local known = row ~= nil and row ~= false and ctx.known[row[2]] == true
            if kind or (level > 0 and not known) then
                local offer = {
                    index = service.index, key = key, name = service.name, level = level, kind = kind,
                    icon = service.icon, rank = service.rank, cost = service.cost, isProfession = service.isProfession == true,
                    id = row and row[2] or nil, needs = row and row.needs or nil, talent = row and row.talent or nil,
                }
                if Rules.ServiceOpen(kind, level, ctx.level, known) then
                    open[#open + 1] = offer
                else
                    waiting[#waiting + 1] = offer
                end
            end
        end
    end
    return open, waiting
end

-- A weapon master's and a pet trainer's services never match a class row.
function Rules.HasClassOffer(open, waiting)
    for _, offer in ipairs(open) do
        if offer.id then return true end
    end
    for _, offer in ipairs(waiting) do
        if offer.id then return true end
    end
    return false
end

function Rules.DefaultTick(offer, skipped)
    if offer.isProfession then return false end
    if offer.id and skipped[offer.id] then return false end
    return true
end

function Rules.CanTick(offer, freeSlots)
    return not offer.isProfession or freeSlots > 0
end

-- Tick all gives each open service the tick a new window gives it; untick all clears them.
function Rules.TickAll(offers, on, skipped, freeSlots, ticks)
    for _, offer in ipairs(offers) do
        ticks[offer.key] = on == true and Rules.DefaultTick(offer, skipped) and Rules.CanTick(offer, freeSlots)
    end
end

-- A service with no quoted cost is never bought: an unknown price is not a free one.
function Rules.BuyPlan(offers, ticks, budget, freeSlots)
    local rows, cost, slots = {}, 0, freeSlots
    for _, offer in ipairs(offers) do
        local price = offer.cost
        if ticks[offer.key] and price and cost + price <= budget and (not offer.isProfession or slots > 0) then
            rows[#rows + 1] = offer
            cost = cost + price
            if offer.isProfession then slots = slots - 1 end
        end
    end
    return rows, cost
end

function Rules.OfferStands(offer, name, kind, level, cost)
    return offer.cost ~= nil and name == offer.name and kind == offer.kind
        and (level or 0) == offer.level and cost == offer.cost
end

-- With nothing to buy it says why, and a row with no price is not called out of reach.
function Rules.LearnLabel(count, costText, ticked, unknown)
    if count > 0 then return ("Learn %d for %s"):format(count, costText) end
    if ticked == 0 then return "Nothing picked" end
    if unknown == ticked then return "No priced spell picked" end
    if unknown > 0 then return "No priced spell you can afford" end
    return "Nothing you can afford"
end

-- earlier: "quest" or "elsewhere" when this window does not list the earlier rank.
function Rules.WaitingText(offer, playerLevel, isKnown, rankText, earlier)
    if offer.level > playerLevel then return "From level " .. offer.level end
    if type(offer.talent) == "number" and not isKnown(offer.talent) then return "Needs a talent" end
    if offer.needs and not isKnown(offer.needs) then
        local rank = rankText ~= "" and rankText or nil
        if earlier == "quest" then return "after " .. (rank or "a rank") .. ", taught by a quest" end
        if earlier == "elsewhere" then return "after " .. (rank or "an earlier rank") end
        if rank then return "after " .. rank .. " above" end
        return "after the rank above"
    end
    return "Not available yet"
end

function Rules.BuyOrder(plan)
    local order = {}
    for i, offer in ipairs(plan) do order[i] = offer end
    sort(order, function(a, b) return a.index > b.index end)
    return order
end

---------------------------------------------------------------------------------
-- Rank swap
---------------------------------------------------------------------------------
function Rules.RankNumber(text)
    if type(text) ~= "string" then return nil end
    return tonumber(text:match("%d+"))
end

function Rules.RankSwaps(best, slots, kept)
    local top = {}
    for _, slot in ipairs(slots) do
        if slot.kind == "spell" and slot.rank and (not top[slot.name] or slot.rank > top[slot.name]) then
            top[slot.name] = slot.rank
        end
    end
    local swaps = {}
    for _, slot in ipairs(slots) do
        local spell = best[slot.name]
        if slot.kind == "spell" and spell and slot.rank and slot.rank < spell.rank
            and slot.rank == top[slot.name] and not kept[slot.name] then
            swaps[#swaps + 1] = { slot = slot.slot, id = spell.id, name = slot.name }
        end
    end
    return swaps
end

---------------------------------------------------------------------------------
-- Route
---------------------------------------------------------------------------------
local function StopTier(npc, side, here, pos, isCapital)
    if here and pos and pos.continent == here.continent then return 1 end
    if isCapital(npc[1]) then return npc[7] == side and 2 or 3 end
    return 4
end

function Rules.NearestStop(npcs, side, here, worldPos, isCapital)
    local best, bestTier, bestDistance
    for _, npc in ipairs(npcs) do
        if Rules.ForFaction(npc, side) then
            local pos = worldPos(npc)
            local tier = StopTier(npc, side, here, pos, isCapital)
            local distance = 0
            if tier == 1 then
                distance = (pos.x - here.x) ^ 2 + (pos.y - here.y) ^ 2
            end
            if not best or tier < bestTier
                or (tier == bestTier and (distance < bestDistance
                    or (distance == bestDistance and npc[4] < best[4]))) then
                best, bestTier, bestDistance = npc, tier, distance
            end
        end
    end
    return best
end

---------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------
function Rules.Coins(copper, paint)
    local gold, silver, rest = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. paint("gold", "g") end
    if silver > 0 then parts[#parts + 1] = silver .. paint("silver", "s") end
    if rest > 0 then parts[#parts + 1] = rest .. paint("copper", "c") end
    if #parts == 0 then return "0" .. paint("copper", "c") end
    return concat(parts, " ")
end

local function UnpricedTail(count)
    return count > 0 and (" + " .. count .. " unpriced") or ""
end

function Rules.TotalText(copper, approx, unpriced, coins)
    local count = unpriced or 0
    if copper == 0 and count > 0 then return count .. " unpriced" end
    return (approx and "~" or "") .. coins(copper) .. UnpricedTail(count)
end

-- What the gold leaves after a running cost, or lacks. Its unpriced spells are in
-- neither figure, so their count rides along, even when the two are equal.
function Rules.Balance(copper, approx, unpriced, gold, coins)
    local short = copper > gold
    local text = Rules.TotalText(short and copper - gold or gold - copper, approx, 0, coins)
    return short, text .. (short and " short" or " spare") .. UnpricedTail(unpriced or 0)
end

local function CostText(section, coins)
    return Rules.TotalText(section.copper, section.approx, section.unpriced, coins)
end

local function SpellCount(count)
    return count == 1 and "1 spell" or (count .. " spells")
end

-- An unpriced row can be neither afforded nor out of reach, so it counts for neither.
-- Counting cheapest first gives how many the gold can pay for, whatever the row order.
function Rules.ToastLine(plan, gold, coins)
    local now = plan.now
    local count, costs = #now.rows, {}
    for _, entry in ipairs(now.rows) do
        if entry.mark ~= "none" then costs[#costs + 1] = entry.copper end
    end
    sort(costs)
    local priced, afford, spent = #costs, 0, 0
    for _, cost in ipairs(costs) do
        spent = spent + cost
        if spent > gold then break end
        afford = afford + 1
    end
    local tail
    if priced == 0 then
        tail = count == 1 and "The trainer shows its price." or "The trainer shows their prices."
    elseif count == 1 then
        tail = afford == 1 and "You can afford it." or "You cannot afford it yet."
    elseif afford == priced then
        tail = priced == count and "You can afford all of them." or "You can afford every priced one."
    elseif afford == 0 then
        tail = priced == count and "You cannot afford any of them yet." or "You cannot afford any priced one yet."
    else
        tail = "You can afford " .. afford .. (priced == count and " of them." or " of the priced ones.")
    end
    return SpellCount(count) .. " to train, " .. CostText(now, coins) .. " in all. " .. tail
end

function Rules.ChatLine(level, plan, coins)
    return "Level " .. level .. ". " .. SpellCount(#plan.now.rows) .. " to train, " .. CostText(plan.now, coins) .. "."
end
