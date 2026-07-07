-- extract-trash-data.lua — deterministic port of ExBoss / DungeonAlerts
-- dungeon-trash cast-timer data into KitnEssentials.
--
-- Run from the repo ROOT with the local Lua 5.1 interpreter:
--   lua dev/scripts/extract-trash-data.lua
--
-- Loads the pure-data source tables by dofile (so every spellID / timing is
-- copied by the interpreter, never retyped), decodes each mob's packed
-- identity bitfield with a verbatim port of ExBoss's EXDB._r, then emits:
--   Modules/DungeonTimers/Trash/TrashData.lua    (KE.TrashData)
--   Modules/DungeonTimers/Trash/TrashTraits.lua  (KE.TrashTraits)
--   dev/docs/dungeon-trash-data-discrepancies.md (cross-build diff)
--
-- Sources (References/ is gitignored — present only on the maintainer box):
--   PRIMARY  EXBoss v26.6.29.1618  (newest — source of truth)
--   DIFF     EXBoss v26.6.4.1821, EXBoss v26.5.12.2252, DungeonAlerts v1
-- Precedence for the discrepancy log: v26.6.29 > v26.6.4 > v26.5.12 > DA.
-- ExBoss always wins; nothing is silently reconciled — every field that
-- differs across builds is logged for human review.
--
-- The Trash/ output directory must already exist (it does once these files
-- are committed). Re-running overwrites the three generated files in place.

---------------------------------------------------------------------------
-- Paths (relative to repo root — the documented CWD)
---------------------------------------------------------------------------

local REF        = "References/ExBoss/"
local PRIMARY    = REF .. "EXBoss-v26.6.29.1618/EXBossData/"
local OLD_664    = REF .. "EXBoss-v26.6.4.1821_old/EXBossData/"
local OLD_6512   = REF .. "EXBoss-v26.5.12.2252_old/EXBossData/"
local DA_DATA    = "References/DungeonAlerts/Dungeon Alerts v1/Data/"

local OUT_DATA   = "Modules/DungeonTimers/Trash/TrashData.lua"
local OUT_TRAITS = "Modules/DungeonTimers/Trash/TrashTraits.lua"
local OUT_DIFF   = "dev/docs/dungeon-trash-data-discrepancies.md"

-- mapID -> KE dungeon key + English display name. Keys match the existing
-- DungeonTimers sidebar ids; names are the live Blizzard dungeon names.
local DUNGEONS = {
    [658]  = { key = "PitOfSaron",       name = "Pit of Saron" },
    [1209] = { key = "Skyreach",         name = "Skyreach" },
    [1753] = { key = "SeatOfTriumvirate", name = "Seat of the Triumvirate" },
    [2526] = { key = "AlgetharAcademy",  name = "Algeth'ar Academy" },
    [2805] = { key = "WindrunnerSpire",  name = "Windrunner Spire" },
    [2811] = { key = "MagistersTerrace", name = "Magisters' Terrace" },
    [2874] = { key = "MaisaraCaverns",   name = "Maisara Caverns" },
    [2915] = { key = "NexusPointXenas",  name = "Nexus-Point Xenas" },
}

---------------------------------------------------------------------------
-- Source loader — dofile each pure-data file into an isolated environment
-- so the four TrashCDData builds don't clobber one another's globals.
---------------------------------------------------------------------------

local function loadDataFile(path)
    local chunk, err = loadfile(path)
    if not chunk then
        error("cannot load " .. path .. "\n  " .. tostring(err))
    end
    -- Fresh env; reads of math/type/tonumber fall through to the real _G,
    -- writes (`_G.FOO = ...`) land in env because env._G == env.
    local env = setmetatable({}, { __index = _G })
    env._G = env
    setfenv(chunk, env)
    local ok, e = pcall(chunk)
    if not ok then
        error("error running " .. path .. "\n  " .. tostring(e))
    end
    return env
end

---------------------------------------------------------------------------
-- Identity bitfield decoder — VERBATIM port of EXDB._r
-- (References/ExBoss/EXBoss-v26.6.29.1618/ExwindCore/Core/ExwindDB.lua:877).
---------------------------------------------------------------------------

local function decodeIdentity(p)
    p = tonumber(p) or 0
    local function b(s, w) return math.floor(p / (2 ^ s)) % (2 ^ w) end
    return {
        buffCount        = b(0, 4),
        classID          = b(4, 4),
        sex              = b(8, 3),
        power            = b(11, 3),
        level            = b(14, 7),
        hasCastSkill     = b(37, 1) == 1,
        noCastSkill      = b(38, 1) == 1,
        hasCastSpell     = b(39, 1) == 1,
        hasChannelSpell  = b(40, 1) == 1,
        hasInterruptFlag = b(41, 1) == 1,
        cannotInterrupt  = b(42, 1) == 1,
        nonElite         = b(43, 1) == 1,
    }
end

-- Field order for the serialized identity table (matches _r's declaration).
local IDENTITY_ORDER = {
    "level", "sex", "power", "classID", "buffCount",
    "hasCastSkill", "noCastSkill", "hasCastSpell", "hasChannelSpell",
    "hasInterruptFlag", "cannotInterrupt", "nonElite",
}

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------

local function fmtNum(n)
    if type(n) ~= "number" then return tostring(n) end
    if math.floor(n) == n and math.abs(n) < 1e15 then
        return string.format("%d", n)
    end
    return string.format("%.14g", n)
end

-- Manual hex so the 40+-bit packed identity round-trips exactly regardless
-- of the interpreter's lua_Integer width.
local function fmtHex(n)
    n = math.floor(n)
    if n == 0 then return "0x0" end
    local digits, s = "0123456789ABCDEF", ""
    while n > 0 do
        local d = n % 16
        s = digits:sub(d + 1, d + 1) .. s
        n = math.floor(n / 16)
    end
    return "0x" .. s
end

local function luaStr(s)
    return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- Inline "{ a, b, c }" array of numbers.
local function fmtNumArray(arr)
    local parts = {}
    for i = 1, #arr do parts[i] = fmtNum(arr[i]) end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Split "2.5/3.5" or "16574,16575" into a number array (non-numeric tokens
-- kept as-is, though none occur in the current data).
local function parseNumList(s, sep)
    if s == nil then return nil end
    s = tostring(s)
    if s == "" then return nil end
    local out = {}
    for token in s:gmatch("[^" .. sep .. "]+") do
        out[#out + 1] = tonumber(token) or token
    end
    if #out == 0 then return nil end
    return out
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return a < b end)
    return keys
end

---------------------------------------------------------------------------
-- Load sources
---------------------------------------------------------------------------

local primaryEnv = loadDataFile(PRIMARY .. "TrashCDData.lua")
local localeEnv  = loadDataFile(PRIMARY .. "TrashCDLocale.lua")
local presetEnv  = loadDataFile(PRIMARY .. "TrashCDPreset.lua")
local traitsEnv  = loadDataFile(PRIMARY .. "TrashMobTraits.lua")

local CD_DATA = primaryEnv.EXBOSS_TRASH_CD_DATA
local LOCALE  = localeEnv.EXBOSS_TRASH_CD_LOCALE
local PRESET  = presetEnv.EXBOSS_TRASH_CD_PRESET
local TRAITS  = traitsEnv.EXBOSS_TRASH_MOB_TRAITS

assert(CD_DATA, "missing EXBOSS_TRASH_CD_DATA")
assert(LOCALE, "missing EXBOSS_TRASH_CD_LOCALE")
assert(PRESET, "missing EXBOSS_TRASH_CD_PRESET")
assert(TRAITS and TRAITS.rows, "missing EXBOSS_TRASH_MOB_TRAITS")

-- English mob name: locale enUS, else the mob's own English/zh name.
local function mobEnUS(npcID, fallback)
    local loc = LOCALE[npcID]
    if loc and loc.enUS and loc.enUS ~= "" then return loc.enUS end
    return fallback
end

-- zh dungeon name -> mapID, built from the primary data's mapName fields
-- (used to resolve the trait rows, which carry only the Chinese name).
local ZH_TO_MAP = {}
for mapID, dungeon in pairs(CD_DATA) do
    if dungeon.mapName then ZH_TO_MAP[dungeon.mapName] = mapID end
end

---------------------------------------------------------------------------
-- DELIVERABLE 2 — TrashData.lua
---------------------------------------------------------------------------

-- Verbatim timing / fingerprint fields, in serialization order. name/nameEN
-- are handled specially (name := nameEN); spellID is emitted first.
local SPELL_ORDER = {
    "castTime", "channelTime", "first", "cd", "cdMode",
    "targetExists", "targetAPIExists", "castStartChangeTarget",
    "targetClearOnCastStart", "castStartAuraDelta",
    "selfBuffCountDeltaOnSuccess", "channelRefreshOnInterruptible",
    "castTimeExtra", "hidden",
}
local SPELL_KNOWN = { spellID = true, name = true, nameEN = true }
for _, k in ipairs(SPELL_ORDER) do SPELL_KNOWN[k] = true end

local function emitScalar(out, indent, key, value)
    if type(value) == "table" then
        out[#out + 1] = string.format("%s%s = %s,", indent, key, fmtNumArray(value))
    elseif type(value) == "boolean" then
        out[#out + 1] = string.format("%s%s = %s,", indent, key, tostring(value))
    elseif type(value) == "number" then
        out[#out + 1] = string.format("%s%s = %s,", indent, key, fmtNum(value))
    else
        out[#out + 1] = string.format("%s%s = %s,", indent, key, luaStr(value))
    end
end

local unknownFields = {}  -- future-proofing: report any source field we don't model

local function serializeTrashData()
    local out = {}
    local function w(line) out[#out + 1] = line end

    w("-- ╔══════════════════════════════════════════════════════════╗")
    w("-- ║  TrashData.lua                                           ║")
    w("-- ║  Auto-generated by dev/scripts/extract-trash-data.lua.   ║")
    w("-- ║  DO NOT EDIT BY HAND — re-run the extractor to refresh.  ║")
    w("-- ║                                                          ║")
    w("-- ║  Curated dungeon-trash cast-timer data, ported verbatim  ║")
    w("-- ║  from the upstream ExBoss data tables (v26.6.29.1618).   ║")
    w("-- ║  Keyed by mapID, then npcID, then spellID.               ║")
    w("-- ║                                                          ║")
    w("-- ║  Schema:                                                 ║")
    w("-- ║    KE.TrashData[mapID] = {                               ║")
    w("-- ║        mapID, dungeonKey, name,   -- English dungeon name ║")
    w("-- ║        mobs = {                                          ║")
    w("-- ║            [npcID] = {                                   ║")
    w("-- ║                npcID, name,       -- enUS mob name       ║")
    w("-- ║                spells = {                                ║")
    w("-- ║                    [spellID] = {                         ║")
    w("-- ║                        spellID, name,  -- enUS spell name ║")
    w("-- ║                        castTime, channelTime, first,     ║")
    w("-- ║                        cd = { ... }, cdMode,             ║")
    w("-- ║                        -- fingerprints (present when set):║")
    w("-- ║                        targetExists, targetAPIExists,    ║")
    w("-- ║                        castStartChangeTarget,            ║")
    w("-- ║                        targetClearOnCastStart,           ║")
    w("-- ║                        castStartAuraDelta,               ║")
    w("-- ║                        selfBuffCountDeltaOnSuccess,      ║")
    w("-- ║                        channelRefreshOnInterruptible,    ║")
    w("-- ║                        castTimeExtra = { ... },          ║")
    w("-- ║                        -- display defaults (TrashCDPreset):║")
    w("-- ║                        showNameplate,  -- default true   ║")
    w("-- ║                        display,        -- \"bar\"|\"text\"    ║")
    w("-- ║                        roles = { tank, healer, dps },    ║")
    w("-- ║                    },                                     ║")
    w("-- ║                },                                         ║")
    w("-- ║            },                                             ║")
    w("-- ║        },                                                ║")
    w("-- ║    }                                                     ║")
    w("-- ╚══════════════════════════════════════════════════════════╝")
    w("")
    w("---@class KE")
    w("local KE = select(2, ...)")
    w("if not KitnEssentials then return end")
    w("")
    w("KE.TrashData = {")

    local mapCount, mobCount, spellCount = 0, 0, 0

    for _, mapID in ipairs(sortedKeys(CD_DATA)) do
        local dungeon = CD_DATA[mapID]
        local meta = DUNGEONS[mapID] or { key = "Unknown", name = dungeon.mapName or "Unknown" }
        mapCount = mapCount + 1
        w(string.format("    [%d] = {", mapID))
        w(string.format("        mapID = %d,", mapID))
        w(string.format("        dungeonKey = %s,", luaStr(meta.key)))
        w(string.format("        name = %s,", luaStr(meta.name)))
        w("        mobs = {")

        local mobs = dungeon.mobs or {}
        for _, npcID in ipairs(sortedKeys(mobs)) do
            local mob = mobs[npcID]
            mobCount = mobCount + 1
            w(string.format("            [%d] = {", npcID))
            w(string.format("                npcID = %d,", npcID))
            w(string.format("                name = %s,", luaStr(mobEnUS(npcID, mob.name))))
            w("                spells = {")

            local spells = mob.spells or {}
            for _, spellID in ipairs(sortedKeys(spells)) do
                local spell = spells[spellID]
                spellCount = spellCount + 1
                w(string.format("                    [%d] = {", spellID))
                local ind = "                        "
                w(string.format("%sspellID = %d,", ind, spellID))
                w(string.format("%sname = %s,", ind, luaStr(spell.nameEN or spell.name)))

                for _, key in ipairs(SPELL_ORDER) do
                    if spell[key] ~= nil then emitScalar(out, ind, key, spell[key]) end
                end
                -- Copy any source field we don't explicitly model (data guard).
                for _, key in ipairs(sortedKeys(spell)) do
                    if type(key) == "string" and not SPELL_KNOWN[key] then
                        unknownFields[key] = (unknownFields[key] or 0) + 1
                        emitScalar(out, ind, key, spell[key])
                    end
                end

                -- A spell the upstream carries with no `first` cast time (and
                -- thus no `cd`) can never schedule a predicted timer bar — mark
                -- it hidden so consumers skip it by default. Deterministic
                -- derivation from the source, not an invented timing value.
                -- (A real source `hidden` field, if one ever appears, is copied
                -- verbatim above via SPELL_ORDER, so don't double-emit here.)
                if spell.first == nil and spell.hidden == nil then
                    w(string.format("%shidden = true,", ind))
                end

                -- Display defaults from TrashCDPreset.
                local preset = PRESET[mapID] and PRESET[mapID][npcID] and PRESET[mapID][npcID][spellID]
                local showNameplate = true
                local display = "bar"
                local tank, healer, dps = true, true, true
                if preset then
                    if preset.showNameplate ~= nil then showNameplate = preset.showNameplate end
                    display = (preset.showTimerBar == false) and "text" or "bar"
                    tank   = preset.tankEnabled   ~= false
                    healer = preset.healerEnabled ~= false
                    dps    = preset.dpsEnabled    ~= false
                end
                w(string.format("%sshowNameplate = %s,", ind, tostring(showNameplate)))
                w(string.format("%sdisplay = %s,", ind, luaStr(display)))
                w(string.format("%sroles = { tank = %s, healer = %s, dps = %s },",
                    ind, tostring(tank), tostring(healer), tostring(dps)))
                w("                    },")
            end

            w("                },")
            w("            },")
        end

        w("        },")
        w("    },")
    end

    w("}")
    w("")
    return table.concat(out, "\n"), mapCount, mobCount, spellCount
end

---------------------------------------------------------------------------
-- DELIVERABLE 3 — TrashTraits.lua
---------------------------------------------------------------------------

local function serializeTrashTraits()
    local out = {}
    local function w(line) out[#out + 1] = line end

    w("-- ╔══════════════════════════════════════════════════════════╗")
    w("-- ║  TrashTraits.lua                                         ║")
    w("-- ║  Auto-generated by dev/scripts/extract-trash-data.lua.   ║")
    w("-- ║  DO NOT EDIT BY HAND — re-run the extractor to refresh.  ║")
    w("-- ║                                                          ║")
    w("-- ║  Per-mob identity fingerprints, ported from ExBoss's     ║")
    w("-- ║  TrashMobTraits rows (v26.6.29.1618). The packed hex     ║")
    w("-- ║  identity is decoded via a verbatim port of EXDB._r.     ║")
    w("-- ║  Keyed by npcID.                                         ║")
    w("-- ║                                                          ║")
    w("-- ║  Schema:                                                 ║")
    w("-- ║    KE.TrashTraits[npcID] = {                             ║")
    w("-- ║        npcID, mapID, dungeonKey,                         ║")
    w("-- ║        identity = { level, sex, power, classID,          ║")
    w("-- ║            buffCount, hasCastSkill, noCastSkill,         ║")
    w("-- ║            hasCastSpell, hasChannelSpell,                ║")
    w("-- ║            hasInterruptFlag, cannotInterrupt, nonElite }, ║")
    w("-- ║        placement,    -- verbatim CSV nameplate slot set  ║")
    w("-- ║        castTimeSet,  -- parsed cast-time numbers         ║")
    w("-- ║        channelTimeSet,                                   ║")
    w("-- ║        spellIDs = { ... },                               ║")
    w("-- ║        packedIdentity, -- raw hex, for runtime verify    ║")
    w("-- ║    }                                                     ║")
    w("-- ╚══════════════════════════════════════════════════════════╝")
    w("")
    w("---@class KE")
    w("local KE = select(2, ...)")
    w("if not KitnEssentials then return end")
    w("")
    w("KE.TrashTraits = {")

    -- Index rows by npcID, sorted for deterministic output.
    local byNpc = {}
    for _, row in ipairs(TRAITS.rows) do
        local npcID = row[3]
        byNpc[npcID] = row
    end

    local traitCount = 0
    for _, npcID in ipairs(sortedKeys(byNpc)) do
        local row = byNpc[npcID]
        local packed       = row[1]
        local dungeonZH    = row[2]
        local placement    = row[5]
        local castTimeCSV  = row[6]
        local channelCSV   = row[7]
        local spellIDs     = row[8] or {}

        local mapID = ZH_TO_MAP[dungeonZH]
        local meta  = mapID and DUNGEONS[mapID]
        if not meta then
            error("trait row npc " .. tostring(npcID) ..
                " has unmapped dungeon " .. tostring(dungeonZH))
        end

        local id = decodeIdentity(packed)
        traitCount = traitCount + 1

        w(string.format("    [%d] = {", npcID))
        w(string.format("        npcID = %d,", npcID))
        w(string.format("        mapID = %d,", mapID))
        w(string.format("        dungeonKey = %s,", luaStr(meta.key)))

        local idParts = {}
        for _, k in ipairs(IDENTITY_ORDER) do
            local v = id[k]
            if type(v) == "boolean" then
                idParts[#idParts + 1] = string.format("%s = %s", k, tostring(v))
            else
                idParts[#idParts + 1] = string.format("%s = %s", k, fmtNum(v))
            end
        end
        w(string.format("        identity = { %s },", table.concat(idParts, ", ")))

        w(string.format("        placement = %s,", luaStr(placement or "")))

        local castSet = parseNumList(castTimeCSV, "/")
        if castSet then
            w(string.format("        castTimeSet = %s,", fmtNumArray(castSet)))
        end
        local chanSet = parseNumList(channelCSV, "/")
        if chanSet then
            w(string.format("        channelTimeSet = %s,", fmtNumArray(chanSet)))
        end

        local spParts = {}
        for i = 1, #spellIDs do spParts[i] = fmtNum(spellIDs[i]) end
        w(string.format("        spellIDs = { %s },", table.concat(spParts, ", ")))

        w(string.format("        packedIdentity = %s,", fmtHex(packed)))
        w("    },")
    end

    w("}")
    w("")
    return table.concat(out, "\n"), traitCount
end

---------------------------------------------------------------------------
-- DELIVERABLE 4 — discrepancy report
---------------------------------------------------------------------------

local DIFF_FIELDS = {
    "castTime", "channelTime", "first", "cd", "cdMode",
    "targetExists", "targetAPIExists", "castStartChangeTarget",
    "targetClearOnCastStart", "castStartAuraDelta",
    "selfBuffCountDeltaOnSuccess", "channelRefreshOnInterruptible",
    "castTimeExtra",
}

-- Canonical string form so absent-field / array / scalar all compare cleanly.
local function canon(v)
    if v == nil then return "\0nil" end
    if type(v) == "table" then
        local parts = {}
        for i = 1, #v do parts[i] = fmtNum(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    if type(v) == "boolean" then return tostring(v) end
    if type(v) == "number" then return fmtNum(v) end
    return tostring(v)
end

-- Human display of a field value inside the report table.
local function showVal(v)
    if v == nil then return "nil" end
    if type(v) == "table" then return fmtNumArray(v) end
    if type(v) == "boolean" then return tostring(v) end
    if type(v) == "number" then return fmtNum(v) end
    return tostring(v)
end

local function generateDiff()
    local sources = {
        { label = "v26.6.29", env = CD_DATA },
        { label = "v26.6.4",  env = loadDataFile(OLD_664 .. "TrashCDData.lua").EXBOSS_TRASH_CD_DATA },
        { label = "v26.5.12", env = loadDataFile(OLD_6512 .. "TrashCDData.lua").EXBOSS_TRASH_CD_DATA },
        { label = "DA v1",    env = loadDataFile(DA_DATA .. "TrashCDData.lua").DA_TRASH_CD_DATA },
    }

    -- spellLookup[mapID][npcID][spellID][sourceIndex] = spell table
    -- mobPresence[mapID][npcID][sourceIndex] = true
    local spellLookup, mobPresence, mapSet, npcNameZH = {}, {}, {}, {}
    for si, src in ipairs(sources) do
        for mapID, dungeon in pairs(src.env or {}) do
            mapSet[mapID] = true
            spellLookup[mapID] = spellLookup[mapID] or {}
            mobPresence[mapID] = mobPresence[mapID] or {}
            for npcID, mob in pairs(dungeon.mobs or {}) do
                mobPresence[mapID][npcID] = mobPresence[mapID][npcID] or {}
                mobPresence[mapID][npcID][si] = true
                npcNameZH[npcID] = npcNameZH[npcID] or mob.name
                spellLookup[mapID][npcID] = spellLookup[mapID][npcID] or {}
                for spellID, spell in pairs(mob.spells or {}) do
                    spellLookup[mapID][npcID][spellID] =
                        spellLookup[mapID][npcID][spellID] or {}
                    spellLookup[mapID][npcID][spellID][si] = spell
                end
            end
        end
    end

    local out, diffCount = {}, 0
    local function w(line) out[#out + 1] = line end

    w("# Dungeon-trash data discrepancies")
    w("")
    w("Auto-generated by `dev/scripts/extract-trash-data.lua`. Every field that")
    w("differs across the four source builds is logged below for human review —")
    w("nothing is silently reconciled.")
    w("")
    w("**Primary source of truth: ExBoss v26.6.29.1618** (newer than the")
    w("v26.6.4 build originally requested). Precedence, highest first:")
    w("**v26.6.29 > v26.6.4 > v26.5.12 > DungeonAlerts v1.** ExBoss always wins;")
    w("the DungeonTimers Trash data ships the v26.6.29 values. This log exists so")
    w("timing changes that affect prediction accuracy (`first`, `cd`, `castTime`,")
    w("`channelTime`) are visible rather than buried.")
    w("")
    w("Legend: a cell shows the field's value in that build; `nil` = field absent")
    w("on an otherwise-present spell; `—` = the spell does not exist in that build.")
    w("")

    for _, mapID in ipairs(sortedKeys(mapSet)) do
        local meta = DUNGEONS[mapID] or { key = "?", name = "?" }
        local dungeonLines, dungeonHasContent = {}, false
        local function dw(line) dungeonLines[#dungeonLines + 1] = line end

        -- 1) Field-value discrepancies.
        for _, npcID in ipairs(sortedKeys(spellLookup[mapID] or {})) do
            for _, spellID in ipairs(sortedKeys(spellLookup[mapID][npcID])) do
                local perSrc = spellLookup[mapID][npcID][spellID]
                local rows = {}
                for _, field in ipairs(DIFF_FIELDS) do
                    local seen, values, differ = {}, {}, false
                    for si = 1, #sources do
                        local spell = perSrc[si]
                        if spell then
                            local c = canon(spell[field])
                            values[si] = spell[field]
                            seen[#seen + 1] = c
                        end
                    end
                    for i = 2, #seen do
                        if seen[i] ~= seen[1] then differ = true break end
                    end
                    if differ then
                        local cells = {}
                        for si = 1, #sources do
                            if perSrc[si] then
                                cells[si] = "`" .. showVal(values[si]) .. "`"
                            else
                                cells[si] = "—"
                            end
                        end
                        rows[#rows + 1] = { field = field, cells = cells }
                    end
                end

                if #rows > 0 then
                    diffCount = diffCount + #rows
                    dungeonHasContent = true
                    local enName = mobEnUS(npcID, npcNameZH[npcID] or "?")
                    -- Pick the spell's English name from whichever build has it.
                    local spName
                    for si = 1, #sources do
                        if perSrc[si] and perSrc[si].nameEN then spName = perSrc[si].nameEN break end
                    end
                    dw(string.format("#### %s (%d) — %s (%d)",
                        enName, npcID, spName or "?", spellID))
                    dw("")
                    dw("| field | v26.6.29 | v26.6.4 | v26.5.12 | DA v1 |")
                    dw("|---|---|---|---|---|")
                    for _, r in ipairs(rows) do
                        dw(string.format("| %s | %s | %s | %s | %s |",
                            r.field, r.cells[1], r.cells[2], r.cells[3], r.cells[4]))
                    end
                    dw("")
                end
            end
        end

        -- 2) Presence differences (spell not in all four builds).
        local presenceRows = {}
        for _, npcID in ipairs(sortedKeys(spellLookup[mapID] or {})) do
            for _, spellID in ipairs(sortedKeys(spellLookup[mapID][npcID])) do
                local perSrc = spellLookup[mapID][npcID][spellID]
                local marks, count = {}, 0
                for si = 1, #sources do
                    if perSrc[si] then marks[si] = "yes"; count = count + 1 else marks[si] = "—" end
                end
                if count < #sources then
                    local enName = mobEnUS(npcID, npcNameZH[npcID] or "?")
                    local spName
                    for si = 1, #sources do
                        if perSrc[si] and perSrc[si].nameEN then spName = perSrc[si].nameEN break end
                    end
                    presenceRows[#presenceRows + 1] = string.format(
                        "| %s (%d) | %s (%d) | %s | %s | %s | %s |",
                        enName, npcID, spName or "?", spellID,
                        marks[1], marks[2], marks[3], marks[4])
                end
            end
        end
        if #presenceRows > 0 then
            dungeonHasContent = true
            diffCount = diffCount + #presenceRows
            dw("**Presence differences (spell missing from one or more builds):**")
            dw("")
            dw("| mob | spell | v26.6.29 | v26.6.4 | v26.5.12 | DA v1 |")
            dw("|---|---|---|---|---|---|")
            for _, r in ipairs(presenceRows) do dw(r) end
            dw("")
        end

        if dungeonHasContent then
            w(string.format("## %s — %s (mapID %d)", meta.name, meta.key, mapID))
            w("")
            for _, l in ipairs(dungeonLines) do w(l) end
        end
    end

    if diffCount == 0 then
        w("_No cross-build discrepancies found._")
        w("")
    end

    return table.concat(out, "\n"), diffCount
end

---------------------------------------------------------------------------
-- Emit
---------------------------------------------------------------------------

local function writeFile(path, content)
    local f, err = io.open(path, "w")
    if not f then error("cannot write " .. path .. ": " .. tostring(err)) end
    f:write(content)
    f:close()
end

local dataStr, mapCount, mobCount, spellCount = serializeTrashData()
writeFile(OUT_DATA, dataStr)

local traitsStr, traitCount = serializeTrashTraits()
writeFile(OUT_TRAITS, traitsStr)

local diffStr, diffCount = generateDiff()
writeFile(OUT_DIFF, diffStr)

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------

print("extract-trash-data.lua — done")
print(string.format("  TrashData.lua    : %d dungeons, %d mobs, %d abilities",
    mapCount, mobCount, spellCount))
print(string.format("  TrashTraits.lua  : %d mob fingerprints", traitCount))
print(string.format("  discrepancies    : %d logged in %s", diffCount, OUT_DIFF))
if next(unknownFields) then
    local names = {}
    for k in pairs(unknownFields) do names[#names + 1] = k end
    table.sort(names)
    print("  NOTE unmodeled source fields copied verbatim: " .. table.concat(names, ", "))
end
