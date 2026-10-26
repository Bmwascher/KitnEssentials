-- extract-trash-data.lua: generates the season-2 sections of the dungeon-trash
-- data (TrashData.lua, TrashTraits.lua) from explicit, pinned inputs.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/extract-trash-data.lua --data-root <dir> --names-db <file>
--       --spell-names dev/data/trash-spell-names-enUS.lua
--       --base-data Modules/DungeonTools/DungeonTimers/Trash/TrashData.lua
--       --base-traits Modules/DungeonTools/DungeonTimers/Trash/TrashTraits.lua
--       --registry Modules/DungeonTools/DungeonTimers/DungeonRegistry.lua
--       --season 2 --out <existing candidate directory>
--
-- --data-root holds TrashCDData.lua, TrashMobTraits.lua and TrashCDPreset.lua.
-- Every input is read as a data literal in an empty environment, and the whole
-- input set is validated before anything is written. The only writes are four
-- files in the --out directory: TrashData.lua, TrashTraits.lua,
-- trash-s2-manifest.lua and trash-s2-report.md. The season-1 sections are the
-- base files' own bytes. dev/scripts/promote-trash-data.lua checks a candidate
-- and publishes it. Names are never translated: NPC names come from the name
-- database's enUS column and spell names from the --spell-names projection.

local M = {}

M.S2_PINS = {
    challengeToInstance = {
        [249] = 1762, [250] = 1877, [399] = 2521, [584] = 2859,
        [585] = 2923, [586] = 2825, [587] = 2813, [588] = 2993,
    },
    excluded = {
        { mapID = 2825, npcID = 250478, spellID = 1309947,
          reason = "disabled untimed marker: no first cast and no cooldown" },
    },
    pinnedSpells = {
        { mapID = 1877, npcID = 134600, spellID = 1308113, first = 9.5, channelTime = 9, cd = { 26 } },
        { mapID = 2521, npcID = 190206, spellID = 385536, first = 8.3, channelTime = 10, cd = { 26 } },
    },
    waveRoomID = 94539,
}

local function fail(msg)
    error("extract-trash-data: " .. msg, 0)
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function fmtNum(n)
    if math.floor(n) == n and math.abs(n) < 1e15 then
        return string.format("%d", n)
    end
    return string.format("%.14g", n)
end

local function luaStr(s)
    return '"' .. (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
end

local function fmtValue(v)
    local kind = type(v)
    if kind == "number" then return fmtNum(v) end
    if kind == "string" then return luaStr(v) end
    if kind == "table" then
        local parts = {}
        for i = 1, #v do parts[i] = fmtValue(v[i]) end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    return tostring(v)
end

-- Labels are ASCII dungeon names, so the padding math is byte-safe.
local function boxHeader(w, indent, label)
    local width = 58
    local pad = width - 2 - #label
    if pad < 0 then pad = 0 end
    w(indent .. "-- ╔" .. string.rep("═", width) .. "╗")
    w(indent .. "-- ║  " .. label .. string.rep(" ", pad) .. "║")
    w(indent .. "-- ╚" .. string.rep("═", width) .. "╝")
end

-- Box-drawing characters are 3 UTF-8 bytes each; the prefix carries two.
local function headerLine(indent, label)
    local prefix = indent .. "-- ── " .. label .. " "
    local fill = 76 - (#prefix - 4)
    if fill < 4 then fill = 4 end
    return prefix .. string.rep("─", fill)
end

local function isWhole(v)
    return type(v) == "number" and v % 1 == 0
end

-- A row's key. Every part must be a whole number, so a string ID never
-- stands in for the numeric one it prints like.
local function tupleKey(mapID, npcID, spellID)
    if not (isWhole(mapID) and isWhole(npcID) and isWhole(spellID)) then
        fail(string.format("row key %s:%s:%s is not three whole numbers",
            tostring(mapID), tostring(npcID), tostring(spellID)))
    end
    return string.format("%d:%d:%d", mapID, npcID, spellID)
end

local function isNumberArray(v)
    if type(v) ~= "table" or #v == 0 then return false end
    for k, n in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > #v or k % 1 ~= 0 or type(n) ~= "number" then
            return false
        end
    end
    return true
end

-- Equal number arrays: same length, and each element the same number.
local function sameNumbers(a, b)
    if not (isNumberArray(a) and isNumberArray(b)) or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function checkType(value, want, where)
    if value == nil then return end
    if want == "numbers" then
        if not isNumberArray(value) then fail(where .. " must be a non-empty number array") end
    elseif type(value) ~= want then
        fail(where .. " must be a " .. want)
    end
end

-- A source set ({ [id] = true }) becomes a sorted ID list; empty becomes nil.
local function setToList(v, where)
    if v == nil then return nil end
    if type(v) ~= "table" then fail(where .. " must be a set") end
    local out = {}
    for k, flag in pairs(v) do
        if type(k) ~= "number" or flag ~= true then fail(where .. " must be a set of IDs") end
        out[#out + 1] = k
    end
    if #out == 0 then return nil end
    table.sort(out)
    return out
end

local function parseDurations(v, where)
    if v == nil then return nil end
    if type(v) ~= "string" then fail(where .. " must be a duration string") end
    local out = {}
    for token in v:gmatch("[^/]+") do
        local n = tonumber(token)
        if not n then fail(where .. " has a non-numeric duration " .. token) end
        out[#out + 1] = n
    end
    if #out == 0 then return nil end
    return out
end

---------------------------------------------------------------------------
-- Input loading
---------------------------------------------------------------------------

-- Cuts the table literal opened by the first line matching headPattern and
-- closed by the first following line that is exactly "}".
function M.ExtractLiteral(text, headPattern, label)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = (line:gsub("\r$", ""))
    end
    local head
    for i = 1, #lines do
        if lines[i]:match(headPattern) then head = i; break end
    end
    if not head then fail(label .. ": no data literal found") end
    for j = head + 1, #lines do
        if lines[j] == "}" then
            return "return {\n" .. table.concat(lines, "\n", head + 1, j - 1) .. "\n}"
        end
    end
    fail(label .. ": data literal is not closed")
end

local function checkPureData(v, label, depth)
    if depth > 12 then fail(label .. ": data literal nests too deeply") end
    local kind = type(v)
    if kind == "table" then
        for k, child in pairs(v) do
            checkPureData(k, label, depth + 1)
            checkPureData(child, label, depth + 1)
        end
    elseif kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        fail(label .. ": data literal holds a " .. kind)
    end
end

-- A table constructor keeps only the last of two equal keys, so a repeat is
-- invisible once the literal runs. This reads the compiled literal's tokens
-- and refuses, per table:
--   * a key written twice: `name =`, `[123] =` or `["text"] =`, with any
--     comment allowed before the `=`;
--   * a table that mixes list items with keys, where an item's implicit index
--     could repeat a key. The pinned inputs' tables are pure lists or pure
--     records, so this refuses no real input.
-- Strings and comments are skipped wherever they fall; any other bracketed
-- key form is refused, since the data literals use none.
local function checkDuplicateKeys(source, label)
    local n = #source
    -- The first index at or after i that is not whitespace or a comment.
    local function skip(i)
        while i <= n do
            if source:sub(i, i):match("%s") then
                i = i + 1
            elseif source:sub(i, i + 1) == "--" then
                local long = source:match("^%-%-%[(=*)%[", i)
                if long then
                    local close = source:find("]" .. long .. "]", i, true)
                    if not close then fail(label .. ": unclosed comment") end
                    i = close + #long + 2
                else
                    i = (source:find("\n", i, true) or n) + 1
                end
            else
                return i
            end
        end
        return i
    end
    local stack = {}
    -- One field of the innermost table: a key (recorded) or a list item.
    local function field(kind, key)
        local frame = stack[#stack]
        if not frame then return end
        frame.atStart = false
        frame[kind] = true
        if frame.key and frame.item then fail(label .. ": a table mixes list items with keys") end
        if key then
            if frame.seen[key] then fail(label .. ": key " .. key:sub(3) .. " is written twice in one table") end
            frame.seen[key] = true
        end
    end
    -- A value token: a list item when it opens a field.
    local function value()
        local frame = stack[#stack]
        if frame and frame.atStart then field("item") end
    end
    local i = skip(1)
    while i <= n do
        local c = source:sub(i, i)
        local long = c == "[" and source:match("^%[(=*)%[", i)
        if long then
            value()
            local close = source:find("]" .. long .. "]", i, true)
            if not close then fail(label .. ": unclosed long string") end
            i = close + #long + 2
        elseif c == '"' or c == "'" then
            value()
            local j = i + 1
            while source:sub(j, j) ~= c do
                if j > n then fail(label .. ": unclosed string") end
                if source:sub(j, j) == "\\" then j = j + 1 end
                j = j + 1
            end
            i = j + 1
        elseif c == "{" then
            value()
            stack[#stack + 1] = { seen = {}, atStart = true }
            i = i + 1
        elseif c == "}" then
            stack[#stack] = nil
            i = i + 1
        elseif c == "," or c == ";" then
            if stack[#stack] then stack[#stack].atStart = true end
            i = i + 1
        elseif c == "[" then
            local num, numEnd = source:match("^%[%s*(%-?[%d%.]+)%s*%]()", i)
            local str, strEnd = source:match('^%[%s*"([^"\\]*)"%s*%]()', i)
            local eq = (numEnd or strEnd) and skip(numEnd or strEnd)
            if not eq or source:sub(eq, eq) ~= "=" then fail(label .. ": unsupported key form") end
            if num and tonumber(num) then
                field("key", "n:" .. tostring(tonumber(num)))
            elseif str then
                field("key", "s:" .. str)
            else
                fail(label .. ": unsupported key form")
            end
            i = eq + 1
        elseif c:match("[%a_]") then
            local word, after = source:match("^([%a_][%w_]*)()", i)
            local eq = skip(after)
            if source:sub(eq, eq) == "=" and source:sub(eq + 1, eq + 1) ~= "=" then
                field("key", "s:" .. word)
                i = eq + 1
            else
                value()
                i = after
            end
        else
            -- A number, its sign, or any other value character.
            value()
            i = c:match("[%w%.]") and source:match("^[%w%.]+()", i) or i + 1
        end
        i = skip(i)
    end
end

-- Runs the literal in an empty environment: any call or global read fails,
-- and any non-data value is refused. A repeated key is refused first, from
-- the text, because running the literal would erase it.
function M.LoadLiteral(source, label)
    local chunk, err = loadstring(source, "=" .. label)
    if not chunk then fail(label .. ": " .. tostring(err)) end
    checkDuplicateKeys(source, label)
    setfenv(chunk, {})
    local ok, value = pcall(chunk)
    if not ok then fail(label .. ": " .. tostring(value)) end
    if type(value) ~= "table" then fail(label .. ": literal is not a table") end
    checkPureData(value, label, 0)
    return value
end

function M.ParseRegistry(text, season)
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^%s*{ key = ") then
            local key, name, instanceID, rowSeason = line:match(
                'key = "(%w+)",%s*name = "([^"]+)",.-instanceID = (%d+),%s*season = (%d+)')
            if not key then fail("registry: unreadable row: " .. line) end
            if tonumber(rowSeason) == season then
                out[#out + 1] = { key = key, name = name, instanceID = tonumber(instanceID) }
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Field dispositions: every source field is shipped, joined, replaced or
-- dropped on purpose. An unknown field stops the run.
---------------------------------------------------------------------------

local MAP_FIELDS = { mapID = true, mapName = true, mobs = true }
local MOB_FIELDS = { npcID = true, name = true, spells = true }

local SPELL_FIELDS = {
    spellID = "key", name = "replaced", nameEN = "replaced", eventType = "dropped",
    castTime = "ship", channelTime = "ship", first = "ship", cd = "ship", cdMode = "ship",
    openingCastOrder = "ship", targetExists = "ship", targetAPIExists = "ship",
    targetHostile = "ship",
    allowPriorityPreviewCastStartVoice = "dropped", muteCastStartVoiceDuringCooldown = "dropped",
}

local SPELL_TYPES = {
    castTime = "number", channelTime = "number", first = "number", cd = "numbers",
    cdMode = "string", openingCastOrder = "number", targetExists = "boolean",
    targetAPIExists = "boolean", targetHostile = "boolean",
}

local SHIPPED_SPELL_ORDER = {
    "castTime", "channelTime", "first", "cd", "cdMode", "openingCastOrder",
    "targetExists", "targetAPIExists", "targetHostile",
}

local TRAIT_FIELDS = {
    dungeon = "join", npcID = "key", name = "replaced",
    level = "identity", power = "identity", nonElite = "identity",
    boss = "placement", minimapIDs = "refused when set",
    wmoAreaIDs = "roomNames", mapIDs = "uiMapIDs",
    preCombatChanneling = "identity", isLieutenant = "identity", hasCreatureFamily = "identity",
    groupHasLevel90 = "identity", groupHasCreatureFamily = "identity",
    groupHasLevel90Power0 = "identity", coPresenceNPCIDs = "coPresenceNPCIDs",
    hasCastSkill = "identity", noCastSkill = "identity", hasCastSpell = "identity",
    hasChannelSpell = "identity", hasInterruptFlag = "identity", cannotInterrupt = "identity",
    castTimeSet = "durations", channelTimeSet = "durations",
    spellCount = "dropped", castSpellCount = "dropped", interruptibleSpellCount = "dropped",
    spellIDs = "spellIDs", secondarySignature = "dropped", bossEncounter = "identity",
    priority = "dropped", bossPriorities = "dropped", bossCounts = "dropped",
}

local IDENTITY_TYPES = {
    level = "number", power = "number", nonElite = "boolean",
    hasCastSkill = "boolean", noCastSkill = "boolean", hasCastSpell = "boolean",
    hasChannelSpell = "boolean", hasInterruptFlag = "boolean", cannotInterrupt = "boolean",
    isLieutenant = "boolean", hasCreatureFamily = "boolean", preCombatChanneling = "boolean",
    bossEncounter = "boolean", groupHasLevel90 = "boolean", groupHasCreatureFamily = "boolean",
    groupHasLevel90Power0 = "boolean",
}

local IDENTITY_EMIT = {
    "level", "power", "nonElite", "hasCastSkill", "noCastSkill", "hasCastSpell",
    "hasChannelSpell", "hasInterruptFlag", "cannotInterrupt", "isLieutenant",
    "hasCreatureFamily", "preCombatChanneling", "bossEncounter", "uiMapIDs", "roomNames",
    "coPresenceNPCIDs", "groupHasLevel90", "groupHasCreatureFamily", "groupHasLevel90Power0",
}

---------------------------------------------------------------------------
-- Candidate report
---------------------------------------------------------------------------

local REPORT_AXES = {
    { label = "level", field = "level" },
    { label = "power", field = "power" },
    { label = "classification", field = "nonElite" },
    { label = "lieutenant", field = "isLieutenant" },
    { label = "family", field = "hasCreatureFamily" },
}

-- A declared axis separates two traits only when both declare it with
-- different values: an undeclared axis never rejects a read.
local function declaredApart(va, vb)
    return va ~= nil and vb ~= nil and va ~= vb
end

local UNCONSUMED = {
    { label = "family presence with the family gate off", field = "hasCreatureFamily", apart = declaredApart },
    -- Positive only: seeing the channel selects a true row; its absence
    -- separates nothing, so true against anything else is the gap.
    { label = "pre-combat channel absence", field = "preCombatChanneling",
      apart = function(va, vb) return (va == true) ~= (vb == true) end },
}

-- No report axis other than `skip` separates the two traits.
local function compatibleExcept(a, b, skip)
    for _, axis in ipairs(REPORT_AXES) do
        if axis.field ~= skip and declaredApart(a.identity[axis.field], b.identity[axis.field]) then
            return false
        end
    end
    return true
end

-- A trait with no room rows can appear anywhere; two room-scoped traits
-- meet only in a shared room.
local function roomsCompatible(a, b)
    local ra, rb = a.identity.roomNames, b.identity.roomNames
    if not ra or not rb then return true end
    for _, x in ipairs(ra) do
        for _, y in ipairs(rb) do
            if x == y then return true end
        end
    end
    return false
end

-- Pairs, in npcID order, that `field` alone separates: apart(field) holds,
-- and no other report axis separates them.
local function pairsSeparatedOnlyBy(list, field, apart)
    local sorted = {}
    for i, trait in ipairs(list) do sorted[i] = trait end
    table.sort(sorted, function(a, b) return a.npcID < b.npcID end)
    local out = {}
    for i = 1, #sorted do
        for j = i + 1, #sorted do
            local a, b = sorted[i], sorted[j]
            if apart(a.identity[field], b.identity[field]) and compatibleExcept(a, b, field) then
                out[#out + 1] = { a, b }
            end
        end
    end
    return out
end

local function traitList(group)
    local parts = {}
    for i, trait in ipairs(group) do parts[i] = string.format("%s (%d)", trait.name, trait.npcID) end
    return table.concat(parts, ", ")
end

local function rowList(group, rowsByNpc, nameBySpell)
    local parts = {}
    for _, trait in ipairs(group) do
        for _, row in ipairs(rowsByNpc[trait.npcID] or {}) do
            parts[#parts + 1] = string.format("%d:%d %s", trait.npcID, row.spellID, nameBySpell[row.spellID])
        end
    end
    return parts
end

-- Layer 2's match tolerance (TI.CAST_TIME_TOLERANCE). One measurement can
-- match two declared durations up to twice this apart.
local DURATION_TOLERANCE = 0.20

-- Whether other's row stays a Layer 1 candidate for trait's plate, as the
-- runtime scores it: no report axis but level separates them, and
-- other's level is not below trait's. A plate that reads below a row's level
-- keeps the row; one that reads above it rejects it.
local function competesFor(trait, other)
    if not compatibleExcept(trait, other, "level") then return false end
    local mine, theirs = trait.identity.level, other.identity.level
    return mine == nil or theirs == nil or theirs >= mine
end

-- The positive routes that separate a wave row from every trait that
-- competes for its plate in its room, from declared values only: a declared
-- duration that no competitor's declared duration can be confused with, an
-- interrupt where every competitor declares it cannot be interrupted, and a
-- named trusted companion. Family presence is a read axis under the family
-- gate, so a family-separated trait never competes. The report shows only
-- what declared values prove; observed values at runtime can add routes it
-- does not list.
local function positiveRoutes(trait, shares, nameOf)
    if #shares == 0 then return "its read axes alone" end
    local id, routes = trait.identity, {}
    local function every(test)
        for _, other in ipairs(shares) do
            if not test(other) then return false end
        end
        return true
    end
    for _, set in ipairs({ { field = "castTimeSet", label = "cast" }, { field = "channelTimeSet", label = "channel" } }) do
        for _, d in ipairs(trait[set.field] or {}) do
            local unique = every(function(o)
                for _, od in ipairs(o[set.field] or {}) do
                    if math.abs(od - d) <= 2 * DURATION_TOLERANCE then return false end
                end
                return true
            end)
            if unique then routes[#routes + 1] = string.format("a %s s %s", fmtNum(d), set.label) end
        end
    end
    if id.cannotInterrupt == false and every(function(o) return o.identity.cannotInterrupt == true end) then
        routes[#routes + 1] = "an interrupt"
    end
    for _, npcID in ipairs(id.coPresenceNPCIDs or {}) do
        routes[#routes + 1] = "a trusted companion " .. nameOf(npcID)
    end
    if #routes == 0 then return "none" end
    return table.concat(routes, " or ")
end

local function emitReport(maps, traits, mobsByMap, nameBySpell)
    local out = { "# Season-2 trash data candidate report", "" }
    local function w(line) out[#out + 1] = line end
    local rowsByNpc = {}
    for _, m in ipairs(maps) do
        for _, mob in ipairs(mobsByMap[m.mapID]) do rowsByNpc[mob.npcID] = mob.spells end
    end
    for _, m in ipairs(maps) do
        local mapTraits = {}
        for _, trait in ipairs(traits) do
            if trait.mapID == m.mapID then mapTraits[#mapTraits + 1] = trait end
        end
        w(string.format("## %s (%d)", m.name, m.mapID))
        w("")
        w("### Indistinguishable when one required axis is unread")
        w("")
        local any = false
        for _, axis in ipairs(REPORT_AXES) do
            for _, group in ipairs(pairsSeparatedOnlyBy(mapTraits, axis.field, declaredApart)) do
                any = true
                w("- unread " .. axis.label .. ": " .. traitList(group))
            end
        end
        if not any then w("- none") end
        w("")
        w("### Rows left ambiguous by an unconsumed discriminator")
        w("")
        any = false
        for _, d in ipairs(UNCONSUMED) do
            for _, group in ipairs(pairsSeparatedOnlyBy(mapTraits, d.field, d.apart)) do
                local rows = rowList(group, rowsByNpc, nameBySpell)
                if #rows > 0 then
                    any = true
                    w("- " .. d.label .. ": " .. traitList(group) .. "; rows " .. table.concat(rows, ", "))
                end
            end
        end
        if not any then w("- none") end
        w("")
        local waveTraits = {}
        for _, trait in ipairs(mapTraits) do
            if trait.identity.groupHasLevel90 ~= nil then waveTraits[#waveTraits + 1] = trait end
        end
        if #waveTraits > 0 then
            w("### Wave rows and the room batch rule")
            w("")
            local byNpc = {}
            for _, trait in ipairs(mapTraits) do byNpc[trait.npcID] = trait end
            local function nameOf(npcID)
                local t = byNpc[npcID]
                return t and string.format("%s (%d)", t.name, npcID) or tostring(npcID)
            end
            for _, trait in ipairs(waveTraits) do
                local shares = {}
                for _, other in ipairs(mapTraits) do
                    if other ~= trait and competesFor(trait, other) and roomsCompatible(trait, other) then
                        shares[#shares + 1] = other
                    end
                end
                table.sort(shares, function(a, b) return a.npcID < b.npcID end)
                local rows = rowList({ trait }, rowsByNpc, nameBySpell)
                local rowText = (#rows > 0) and table.concat(rows, ", ") or "identity only"
                local depends = (#shares > 0)
                    and ("yes; competes in its room with " .. traitList(shares)) or "no"
                w(string.format("- %s (%d): level90=%s family=%s level90power0=%s; rows %s; positive routes: %s; early identity depends on the batch rule: %s",
                    trait.name, trait.npcID, tostring(trait.identity.groupHasLevel90),
                    tostring(trait.identity.groupHasCreatureFamily),
                    tostring(trait.identity.groupHasLevel90Power0), rowText,
                    positiveRoutes(trait, shares, nameOf), depends))
            end
            w("")
        end
        w("### Mobs with several start-advance spells of one kind")
        w("")
        any = false
        for _, mob in ipairs(mobsByMap[m.mapID]) do
            local cast, channel = 0, 0
            for _, row in ipairs(mob.spells) do
                if row.spell.cdMode == "CAST_START" then
                    if (row.spell.castTime or 0) > 0 then
                        cast = cast + 1
                    elseif (row.spell.channelTime or 0) > 0 then
                        channel = channel + 1
                    end
                end
            end
            if cast > 1 or channel > 1 then
                any = true
                w(string.format("- %s (%d): %d cast, %d channel", mob.name, mob.npcID, cast, channel))
            end
        end
        if not any then w("- none") end
        w("")
    end
    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Build: validate everything, then render the candidate texts
---------------------------------------------------------------------------

local function displayDefaults(preset, row)
    local byNpc = preset[row.challenge] and preset[row.challenge][row.npcID]
    local p = byNpc and byNpc[row.spellID]
    local showNameplate, display, tank, healer, dps = true, "bar", true, true, true
    if type(p) == "table" then
        if p.showNameplate ~= nil then showNameplate = (p.showNameplate == true) end
        if p.showTimerBar == false then display = "text" end
        tank = p.tankEnabled ~= false
        healer = p.healerEnabled ~= false
        dps = p.dpsEnabled ~= false
    end
    return showNameplate, display, tank, healer, dps
end

local function splicePrefix(base, label)
    if type(base) ~= "string" or not base:match("},\n}\n$") then
        fail(label .. ": base file does not end with its closing brace")
    end
    return base:sub(1, #base - 2)
end

function M.Build(inputs, pins)
    pins = pins or M.S2_PINS
    if type(inputs) ~= "table" or type(inputs.data) ~= "table" then fail("data: malformed input") end
    local preset = inputs.preset or {}

    -- Maps: pinned challenge -> instance, checked against the name database
    -- rows and the registry's season entries.
    local instanceByChallenge = {}
    for _, row in ipairs(inputs.instances or {}) do
        local challenge = tonumber(row.challengeModeID)
        if challenge then
            if instanceByChallenge[challenge] then
                fail("map collision: challenge " .. challenge .. " is listed twice")
            end
            instanceByChallenge[challenge] = row
        end
    end
    local maps, seenInstance = {}, {}
    for _, challenge in ipairs(sortedKeys(pins.challengeToInstance)) do
        local want = pins.challengeToInstance[challenge]
        local row = instanceByChallenge[challenge]
        if not row then fail("challenge " .. challenge .. " has no instance row") end
        if row.mapID ~= want then
            fail("challenge " .. challenge .. " maps to " .. tostring(row.mapID) .. ", pinned " .. want)
        end
        if seenInstance[want] then fail("map collision: instance " .. want .. " is pinned twice") end
        seenInstance[want] = true
        if type(row.name) ~= "string" or row.name == "" then
            fail("instance " .. want .. " has no dungeon name")
        end
        maps[#maps + 1] = { mapID = want, challenge = challenge, zhName = row.name }
    end
    local registryByInstance = {}
    for _, entry in ipairs(inputs.registry or {}) do
        if registryByInstance[entry.instanceID] then
            fail("map collision: the registry lists instance " .. tostring(entry.instanceID) .. " twice")
        end
        registryByInstance[entry.instanceID] = entry
    end
    if #(inputs.registry or {}) ~= #maps then
        fail("the registry's season entries do not match the pinned instances")
    end
    local mapByZh, mapInfo = {}, {}
    for _, m in ipairs(maps) do
        local entry = registryByInstance[m.mapID]
        if not entry then fail("the registry has no season entry for instance " .. m.mapID) end
        m.key, m.name = entry.key, entry.name
        if mapByZh[m.zhName] then fail("map collision: two instances share one dungeon name") end
        mapByZh[m.zhName] = m
        mapInfo[m.mapID] = m
    end
    table.sort(maps, function(a, b) return a.mapID < b.mapID end)
    for challenge in pairs(inputs.data) do
        if not pins.challengeToInstance[challenge] then
            fail("data has an unpinned challenge " .. tostring(challenge))
        end
    end

    -- Spell names.
    local names = inputs.spellNames
    if type(names) ~= "table" or type(names.entries) ~= "table"
        or type(names.includedRows) ~= "table" or type(names.excludedRows) ~= "table" then
        fail("spell names: malformed input")
    end
    if type(names.sourceSha256) ~= "string" or names.sourceSha256 == "" then
        fail("spell names: no source hash")
    end
    local nameBySpell = {}
    for i, entry in ipairs(names.entries) do
        local id, name = entry[1], entry[2]
        if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
            fail("spell names: entry " .. i .. " has no spell ID")
        end
        if type(name) ~= "string" or name == "" then fail("spell names: spell " .. id .. " has an empty name") end
        if nameBySpell[id] then fail("spell names: duplicate spell " .. id) end
        nameBySpell[id] = name
    end
    local included, includedSpells = {}, {}
    for _, t in ipairs(names.includedRows) do
        local key = tupleKey(t[1], t[2], t[3])
        if included[key] then fail("spell names: duplicate row " .. key) end
        included[key] = true
        includedSpells[t[3]] = true
    end
    local excludedByKey, recordedExcluded = {}, {}
    for _, x in ipairs(pins.excluded) do excludedByKey[tupleKey(x.mapID, x.npcID, x.spellID)] = x end
    for _, t in ipairs(names.excludedRows) do recordedExcluded[tupleKey(t[1], t[2], t[3])] = true end
    for _, key in ipairs(sortedKeys(excludedByKey)) do
        if not recordedExcluded[key] then fail("spell names: excluded row " .. key .. " is not recorded") end
    end
    for _, key in ipairs(sortedKeys(recordedExcluded)) do
        if not excludedByKey[key] then fail("spell names: excluded row " .. key .. " is not pinned") end
        if included[key] then fail("spell names: excluded row " .. key .. " is among the included rows") end
    end

    local npcNames = inputs.npcNames or {}
    local function englishNpc(npcID)
        local loc = npcNames[npcID]
        local name = type(loc) == "table" and loc.enUS
        if type(name) ~= "string" or name == "" then fail("npc " .. npcID .. " has no English name") end
        return name
    end

    -- Timer rows.
    local rows, rowByKey, mobsByMap, timerMap, seenExcluded = {}, {}, {}, {}, {}
    for _, m in ipairs(maps) do
        local source = inputs.data[m.challenge]
        if type(source) ~= "table" then fail("data has no challenge " .. m.challenge) end
        for field in pairs(source) do
            if not MAP_FIELDS[field] then fail("map " .. m.mapID .. ": field " .. tostring(field) .. " has no disposition") end
        end
        if source.mapID ~= m.challenge then fail("map " .. m.mapID .. ": inner mapID mismatch") end
        local mobs = {}
        local sourceMobs = source.mobs or {}
        for _, npcID in ipairs(sortedKeys(sourceMobs)) do
            local mob = sourceMobs[npcID]
            for field in pairs(mob) do
                if not MOB_FIELDS[field] then fail("npc " .. npcID .. ": field " .. tostring(field) .. " has no disposition") end
            end
            if mob.npcID ~= npcID then fail("npc " .. npcID .. ": inner npcID mismatch") end
            local spells = {}
            local sourceSpells = mob.spells or {}
            for _, spellID in ipairs(sortedKeys(sourceSpells)) do
                local spell = sourceSpells[spellID]
                local where = tupleKey(m.mapID, npcID, spellID)
                for field in pairs(spell) do
                    if not SPELL_FIELDS[field] then
                        fail(where .. ": field " .. tostring(field) .. " has no disposition")
                    end
                end
                if spell.spellID ~= spellID then fail(where .. ": inner spellID mismatch") end
                if excludedByKey[where] then
                    seenExcluded[where] = true
                else
                    for _, field in ipairs(SHIPPED_SPELL_ORDER) do
                        checkType(spell[field], SPELL_TYPES[field], where .. "." .. field)
                    end
                    if spell.targetHostile ~= nil and (spell.channelTime or 0) > 0 then
                        fail(where .. ": targetHostile on a row with a channel duration")
                    end
                    local row = { mapID = m.mapID, challenge = m.challenge, npcID = npcID,
                        spellID = spellID, spell = spell, hidden = (spell.first == nil) }
                    spells[#spells + 1] = row
                    rows[#rows + 1] = row
                    rowByKey[where] = row
                end
            end
            if #spells > 0 then
                if timerMap[npcID] then fail("npc " .. npcID .. " has timer rows in two maps") end
                timerMap[npcID] = m.mapID
                mobs[#mobs + 1] = { npcID = npcID, name = englishNpc(npcID), spells = spells }
            end
        end
        mobsByMap[m.mapID] = mobs
    end
    for _, key in ipairs(sortedKeys(excludedByKey)) do
        if not seenExcluded[key] then fail("excluded row " .. key .. " is not in the data") end
    end
    for _, p in ipairs(pins.pinnedSpells) do
        local key = tupleKey(p.mapID, p.npcID, p.spellID)
        local row = rowByKey[key]
        if not row then fail("pinned row " .. key .. " is missing") end
        local s = row.spell
        if s.first ~= p.first or s.channelTime ~= p.channelTime or not sameNumbers(s.cd, p.cd) then
            fail("pinned row " .. key .. " does not carry its pinned first cast, channel and cooldown")
        end
    end
    for _, row in ipairs(rows) do
        local key = tupleKey(row.mapID, row.npcID, row.spellID)
        if not included[key] then fail("generated row " .. key .. " is not in the spell-name rows") end
        if not nameBySpell[row.spellID] then fail("no English name for spell " .. row.spellID) end
    end
    for _, key in ipairs(sortedKeys(included)) do
        if not rowByKey[key] then fail("spell-name row " .. key .. " is not generated") end
    end
    for _, id in ipairs(sortedKeys(nameBySpell)) do
        if not includedSpells[id] then fail("spell-name entry " .. id .. " belongs to no included row") end
    end

    -- Traits.
    local traitSource = inputs.traits
    if type(traitSource) ~= "table" or type(traitSource.rows) ~= "table" then fail("traits: malformed input") end
    for field in pairs(traitSource) do
        if field ~= "rows" and field ~= "wmoAreaNamesByID" then
            fail("traits: field " .. tostring(field) .. " has no disposition")
        end
    end
    local roomNameByID = traitSource.wmoAreaNamesByID or {}
    local traits, traitByNpc = {}, {}
    for i, src in ipairs(traitSource.rows) do
        for field in pairs(src) do
            if not TRAIT_FIELDS[field] then
                fail("trait row " .. i .. ": field " .. tostring(field) .. " has no disposition")
            end
        end
        local npcID = src.npcID
        if type(npcID) ~= "number" then fail("trait row " .. i .. " has no npcID") end
        local where = "trait " .. npcID
        if traitByNpc[npcID] then fail(where .. " is listed twice") end
        local m = mapByZh[src.dungeon]
        if not m then fail(where .. ": unmapped dungeon " .. tostring(src.dungeon)) end
        if src.minimapIDs ~= nil then fail(where .. ": minimapIDs is set") end
        if timerMap[npcID] and timerMap[npcID] ~= m.mapID then fail(where .. ": its timer rows are in another map") end
        local identity = {}
        for field, want in pairs(IDENTITY_TYPES) do
            checkType(src[field], want, where .. "." .. field)
            identity[field] = src[field]
        end
        identity.uiMapIDs = setToList(src.mapIDs, where .. ".mapIDs")
        identity.coPresenceNPCIDs = setToList(src.coPresenceNPCIDs, where .. ".coPresenceNPCIDs")
        local roomIDs = setToList(src.wmoAreaIDs, where .. ".wmoAreaIDs")
        if roomIDs then
            local roomNames = {}
            for _, id in ipairs(roomIDs) do
                local loc = roomNameByID[id]
                local name = type(loc) == "table" and loc.enUS
                if type(name) ~= "string" or name == "" then fail(where .. ": room " .. id .. " has no English name") end
                roomNames[#roomNames + 1] = name
            end
            identity.roomNames = roomNames
            if src.wmoAreaIDs[pins.waveRoomID] and (src.groupHasLevel90 == nil
                or src.groupHasCreatureFamily == nil or src.groupHasLevel90Power0 == nil) then
                fail(where .. ": a wave-room trait lacks the three wave fields")
            end
        end
        local placement = src.boss or ""
        if type(placement) ~= "string" then fail(where .. ".boss must be a string") end
        -- A source trait may declare an empty spell list; it ships as declared.
        if src.spellIDs ~= nil and not (type(src.spellIDs) == "table"
            and (next(src.spellIDs) == nil or isNumberArray(src.spellIDs))) then
            fail(where .. ".spellIDs must be a number array, possibly empty")
        end
        local trait = {
            npcID = npcID, mapID = m.mapID, key = m.key, name = englishNpc(npcID),
            identityOnly = (timerMap[npcID] == nil), identity = identity, placement = placement,
            castTimeSet = parseDurations(src.castTimeSet, where .. ".castTimeSet"),
            channelTimeSet = parseDurations(src.channelTimeSet, where .. ".channelTimeSet"),
            spellIDs = src.spellIDs,
        }
        traits[#traits + 1] = trait
        traitByNpc[npcID] = trait
    end
    for _, npcID in ipairs(sortedKeys(timerMap)) do
        if not traitByNpc[npcID] then fail("timer npc " .. npcID .. " has no trait") end
    end
    table.sort(traits, function(a, b)
        if a.mapID ~= b.mapID then return a.mapID < b.mapID end
        return a.npcID < b.npcID
    end)

    -- Render TrashData's season-2 sections.
    local dataPrefix = splicePrefix(inputs.baseData, "TrashData")
    local traitsPrefix = splicePrefix(inputs.baseTraits, "TrashTraits")
    for _, m in ipairs(maps) do
        if dataPrefix:find("\n    [" .. m.mapID .. "] = {", 1, true) then
            fail("TrashData: base already holds map " .. m.mapID)
        end
    end
    for _, trait in ipairs(traits) do
        if traitsPrefix:find("\n    [" .. trait.npcID .. "] = {", 1, true) then
            fail("TrashTraits: base already holds npc " .. trait.npcID)
        end
    end

    local dataLines = {}
    local function wd(line) dataLines[#dataLines + 1] = line end
    local ind = string.rep(" ", 24)
    for i, m in ipairs(maps) do
        if i > 1 then wd("") end
        boxHeader(wd, "    ", string.format("%s (%d)", m.name, m.mapID))
        wd(string.format("    [%d] = {", m.mapID))
        wd(string.format("        mapID = %d,", m.mapID))
        wd("        dungeonKey = " .. luaStr(m.key) .. ",")
        wd("        name = " .. luaStr(m.name) .. ",")
        wd("        mobs = {")
        for j, mob in ipairs(mobsByMap[m.mapID]) do
            if j > 1 then wd("") end
            wd(headerLine("            ", mob.name))
            wd(string.format("            [%d] = {", mob.npcID))
            wd(string.format("                npcID = %d,", mob.npcID))
            wd("                name = " .. luaStr(mob.name) .. ",")
            wd("                spells = {")
            for _, row in ipairs(mob.spells) do
                wd(string.format("                    [%d] = {", row.spellID))
                wd(ind .. "spellID = " .. fmtNum(row.spellID) .. ",")
                wd(ind .. "name = " .. luaStr(nameBySpell[row.spellID]) .. ",")
                for _, field in ipairs(SHIPPED_SPELL_ORDER) do
                    if row.spell[field] ~= nil then wd(ind .. field .. " = " .. fmtValue(row.spell[field]) .. ",") end
                end
                if row.hidden then wd(ind .. "hidden = true,") end
                local showNameplate, display, tank, healer, dps = displayDefaults(preset, row)
                wd(ind .. "showNameplate = " .. tostring(showNameplate) .. ",")
                wd(ind .. "display = " .. luaStr(display) .. ",")
                wd(string.format("%sroles = { tank = %s, healer = %s, dps = %s },",
                    ind, tostring(tank), tostring(healer), tostring(dps)))
                wd("                    },")
            end
            wd("                },")
            wd("            },")
        end
        wd("        },")
        wd("    },")
    end

    -- Render TrashTraits' season-2 sections.
    local traitLines = {}
    local function wt(line) traitLines[#traitLines + 1] = line end
    local lastMap
    for _, trait in ipairs(traits) do
        if trait.mapID ~= lastMap then
            wt("")
            local m = mapInfo[trait.mapID]
            boxHeader(wt, "    ", string.format("%s (%d)", m.name, m.mapID))
            lastMap = trait.mapID
        end
        wt("")
        wt("    -- ── " .. trait.name .. " ──")
        wt(string.format("    [%d] = {", trait.npcID))
        wt(string.format("        npcID = %d,", trait.npcID))
        wt(string.format("        mapID = %d,", trait.mapID))
        wt("        dungeonKey = " .. luaStr(trait.key) .. ",")
        wt("        name = " .. luaStr(trait.name) .. ",")
        wt('        schema = "named",')
        if trait.identityOnly then wt("        identityOnly = true,") end
        local parts = {}
        for _, field in ipairs(IDENTITY_EMIT) do
            if trait.identity[field] ~= nil then
                parts[#parts + 1] = field .. " = " .. fmtValue(trait.identity[field])
            end
        end
        if #parts > 0 then
            wt("        identity = { " .. table.concat(parts, ", ") .. " },")
        else
            wt("        identity = {},")
        end
        wt("        placement = " .. luaStr(trait.placement) .. ",")
        if trait.castTimeSet then wt("        castTimeSet = " .. fmtValue(trait.castTimeSet) .. ",") end
        if trait.channelTimeSet then wt("        channelTimeSet = " .. fmtValue(trait.channelTimeSet) .. ",") end
        if trait.spellIDs then wt("        spellIDs = " .. fmtValue(trait.spellIDs) .. ",") end
        wt("    },")
    end

    -- Counts and manifest.
    local mapCounts = {}
    local totals = { npcs = 0, rows = 0, visibleRows = 0, hiddenRows = 0, traits = 0, identityOnly = 0 }
    for _, m in ipairs(maps) do
        local c = { mapID = m.mapID, dungeonKey = m.key, npcs = #mobsByMap[m.mapID],
            rows = 0, visibleRows = 0, hiddenRows = 0, traits = 0, identityOnly = 0 }
        for _, mob in ipairs(mobsByMap[m.mapID]) do
            for _, row in ipairs(mob.spells) do
                c.rows = c.rows + 1
                if row.hidden then c.hiddenRows = c.hiddenRows + 1 else c.visibleRows = c.visibleRows + 1 end
            end
        end
        for _, trait in ipairs(traits) do
            if trait.mapID == m.mapID then
                c.traits = c.traits + 1
                if trait.identityOnly then c.identityOnly = c.identityOnly + 1 end
            end
        end
        for field in pairs(totals) do totals[field] = totals[field] + c[field] end
        mapCounts[#mapCounts + 1] = c
    end
    local manifest = {
        "-- Generated by dev/scripts/extract-trash-data.lua. Do not edit.",
        "return {",
        "    season = 2,",
        "    spellNamesSha256 = " .. luaStr(names.sourceSha256) .. ",",
        string.format("    totals = { npcs = %d, rows = %d, visibleRows = %d, hiddenRows = %d, traits = %d, identityOnly = %d },",
            totals.npcs, totals.rows, totals.visibleRows, totals.hiddenRows, totals.traits, totals.identityOnly),
        "    maps = {",
    }
    for _, c in ipairs(mapCounts) do
        manifest[#manifest + 1] = string.format(
            "        { mapID = %d, dungeonKey = %s, npcs = %d, rows = %d, visibleRows = %d, hiddenRows = %d, traits = %d, identityOnly = %d },",
            c.mapID, luaStr(c.dungeonKey), c.npcs, c.rows, c.visibleRows, c.hiddenRows, c.traits, c.identityOnly)
    end
    manifest[#manifest + 1] = "    },"
    manifest[#manifest + 1] = "    excluded = {"
    for _, x in ipairs(pins.excluded) do
        manifest[#manifest + 1] = string.format("        { mapID = %d, npcID = %d, spellID = %d, reason = %s },",
            x.mapID, x.npcID, x.spellID, luaStr(x.reason))
    end
    manifest[#manifest + 1] = "    },"
    manifest[#manifest + 1] = "}"

    return {
        data = dataPrefix .. "\n" .. table.concat(dataLines, "\n") .. "\n}\n",
        traits = traitsPrefix .. table.concat(traitLines, "\n") .. "\n}\n",
        manifest = table.concat(manifest, "\n") .. "\n",
        report = emitReport(maps, traits, mobsByMap, nameBySpell) .. "\n",
        maps = mapCounts,
        totals = totals,
    }
end

---------------------------------------------------------------------------
-- Run: read, parse, build, then write the candidate
---------------------------------------------------------------------------

M.realFS = {
    read = function(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local text = f:read("*a")
        f:close()
        return text
    end,
    write = function(path, text)
        local f, err = io.open(path, "wb")
        if not f then return nil, err end
        f:write(text)
        f:close()
        return true
    end,
}

local REQUIRED_OPTIONS = {
    "data-root", "names-db", "spell-names", "base-data", "base-traits", "registry", "season", "out",
}

local INPUT_ORDER = { "data", "traits", "preset", "names", "spellNames", "baseData", "baseTraits", "registry" }

function M.Run(opts, fs)
    fs = fs or M.realFS
    return pcall(function()
        for _, option in ipairs(REQUIRED_OPTIONS) do
            if type(opts[option]) ~= "string" or opts[option] == "" then fail("missing --" .. option) end
        end
        if opts.season ~= "2" then fail("--season must be 2") end
        local root = opts["data-root"]:gsub("[/\\]+$", "")
        local paths = {
            data = root .. "/TrashCDData.lua",
            traits = root .. "/TrashMobTraits.lua",
            preset = root .. "/TrashCDPreset.lua",
            names = opts["names-db"],
            spellNames = opts["spell-names"],
            baseData = opts["base-data"],
            baseTraits = opts["base-traits"],
            registry = opts.registry,
        }
        local text = {}
        for _, key in ipairs(INPUT_ORDER) do
            text[key] = fs.read(paths[key])
            if not text[key] then fail("missing input " .. paths[key]) end
        end
        local inputs = {
            data = M.LoadLiteral(M.ExtractLiteral(text.data,
                "^_G%.[%w_]+_TRASH_CD_DATA = {%s*$", "data"), "data"),
            traits = M.LoadLiteral(M.ExtractLiteral(text.traits,
                "^_G%.[%w_]+_TRASH_MOB_TRAITS = {%s*$", "traits"), "traits"),
            preset = M.LoadLiteral(M.ExtractLiteral(text.preset,
                "^_G%.[%w_]+_TRASH_CD_PRESET = {%s*$", "preset"), "preset"),
            npcNames = M.LoadLiteral(M.ExtractLiteral(text.names,
                "^[%w_]+%.NPCNameSource = {%s*$", "npc names"), "npc names"),
            instances = M.LoadLiteral(M.ExtractLiteral(text.names,
                "^[%w_]+%.InstanceNoteInstanceSource = {%s*$", "instances"), "instances"),
            spellNames = M.LoadLiteral(text.spellNames, "spell names"),
            registry = M.ParseRegistry(text.registry, 2),
            baseData = text.baseData,
            baseTraits = text.baseTraits,
        }
        local built = M.Build(inputs)
        local outDir = opts.out:gsub("[/\\]+$", "")
        local files = {
            { "TrashData.lua", built.data },
            { "TrashTraits.lua", built.traits },
            { "trash-s2-manifest.lua", built.manifest },
            { "trash-s2-report.md", built.report },
        }
        for _, file in ipairs(files) do
            local ok, err = fs.write(outDir .. "/" .. file[1], file[2])
            if not ok then fail("cannot write " .. file[1] .. ": " .. tostring(err)) end
        end
        return built
    end)
end

local function parseArgs(argv)
    local opts = {}
    local i = 1
    while argv[i] ~= nil do
        local option = argv[i]:match("^%-%-([%w%-]+)$")
        if not option or argv[i + 1] == nil then return nil, "bad argument " .. tostring(argv[i]) end
        opts[option] = argv[i + 1]
        i = i + 2
    end
    return opts
end

if arg and type(arg[0]) == "string" and arg[0]:match("extract%-trash%-data%.lua$") then
    local opts, argErr = parseArgs(arg)
    if not opts then
        io.stderr:write("extract-trash-data: " .. argErr .. "\n")
        os.exit(2)
    end
    local ok, result = M.Run(opts)
    if not ok then
        io.stderr:write(tostring(result) .. "\n")
        os.exit(1)
    end
    for _, c in ipairs(result.maps) do
        print(string.format("%-20s npcs %3d rows %3d visible %3d hidden %d traits %3d identity-only %3d",
            c.dungeonKey, c.npcs, c.rows, c.visibleRows, c.hiddenRows, c.traits, c.identityOnly))
    end
    local t = result.totals
    print(string.format("total npcs %d rows %d visible %d hidden %d traits %d identity-only %d",
        t.npcs, t.rows, t.visibleRows, t.hiddenRows, t.traits, t.identityOnly))
end

return M
