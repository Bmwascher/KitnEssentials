-- Lint: the two frame data tables in Modules/QoL/MoveFrames.lua. A frame
-- name on the wrong key shape, a duplicate, or a non-Blizzard_ addon key is
-- silently skipped in game, so the shape is pinned here. The tables are
-- reached through the loader's debug.getupvalue seam, never exported.
local L = require("dev.spec._ke_loader")

-- Collects frame names per the counting rule. skipTopStringKeys is true only
-- for the very top level of BlizzardFramesOnDemand, where string keys are
-- ADDON names rather than frame names and must not be collected.
local function collectNames(t, skipTopStringKeys, names)
    for k, v in pairs(t) do
        if type(k) == "number" and type(v) == "string" then
            names[#names + 1] = v
        elseif type(k) == "string" and type(v) == "table" then
            if not skipTopStringKeys then
                names[#names + 1] = k
            end
            collectNames(v, false, names)
        end
    end
end

-- Recursively checks that every numeric key holds a string and every string
-- key holds a table, everywhere in t.
local function structuralViolations(t, path, violations)
    for k, v in pairs(t) do
        if type(k) == "number" then
            if type(v) ~= "string" then
                violations[#violations + 1] = path .. "[" .. tostring(k) .. "] is a " .. type(v) .. ", not a string"
            end
        elseif type(k) == "string" then
            if type(v) ~= "table" then
                violations[#violations + 1] = path .. "." .. k .. " is a " .. type(v) .. ", not a table"
            else
                structuralViolations(v, path .. "." .. k, violations)
            end
        end
    end
end

-- Whether target appears anywhere in t, either as a numeric-keyed leaf string
-- or as a string key naming a nested table.
local function containsName(t, target)
    for k, v in pairs(t) do
        if type(k) == "number" and type(v) == "string" and v == target then
            return true
        elseif type(k) == "string" and type(v) == "table" then
            if k == target or containsName(v, target) then
                return true
            end
        end
    end
    return false
end

describe("MoveFrames.lua frame tables", function()
    local seams

    before_each(function()
        local _, _, s = L.loadMoveFrames()
        seams = s
    end)

    describe("frame-table structural integrity", function()
        it("holds only strings on numeric keys and only tables on string keys, in BlizzardFrames", function()
            local violations = {}
            structuralViolations(seams.blizzardFrames, "BlizzardFrames", violations)
            assert.same({}, violations)
        end)

        it("holds only strings on numeric keys and only tables on string keys, in BlizzardFramesOnDemand", function()
            local violations = {}
            structuralViolations(seams.blizzardFramesOnDemand, "BlizzardFramesOnDemand", violations)
            assert.same({}, violations)
        end)

        it("has no duplicate frame name in BlizzardFrames", function()
            local names = {}
            collectNames(seams.blizzardFrames, false, names)
            local seen, dupes = {}, {}
            for _, name in ipairs(names) do
                if seen[name] then
                    dupes[#dupes + 1] = name
                end
                seen[name] = true
            end
            assert.same({}, dupes)
        end)

        it("has only Blizzard_-prefixed top-level keys in BlizzardFramesOnDemand", function()
            for k in pairs(seams.blizzardFramesOnDemand) do
                assert.is_true(type(k) == "string" and k:sub(1, 9) == "Blizzard_", "unexpected top-level key: " .. tostring(k))
            end
        end)
    end)

    describe("frame-table content", function()
        it("never carries GameMenuFrame in either table (regression guard)", function()
            assert.is_false(containsName(seams.blizzardFrames, "GameMenuFrame"))
            assert.is_false(containsName(seams.blizzardFramesOnDemand, "GameMenuFrame"))
        end)
    end)
end)
