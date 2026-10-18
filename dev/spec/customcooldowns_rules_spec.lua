-- Modules/Combat/ClassTools/CustomCooldownsRules.lua -- the rules a later edit
-- breaks silently: what the add and remove controls refuse in each scope, and
-- which spells the current spec shows.
local L = require("dev.spec._ke_loader")

describe("custom cooldowns rules", function()
    local Rules

    before_each(function()
        Rules = L.loadCustomCooldownsRules().CustomCooldownsRules
    end)

    local function nameOf(id)
        if id == 99999 then return nil end
        return "Spell " .. id
    end

    it("adds and removes per scope: All Specs under the class token, one spec under its id", function()
        local NOT_ID = "Enter a spell id (a whole number)."
        local THERE = "That spell is already listed there."
        local ALL = "That spell is already listed for all specs."
        local NOT_THERE = "That id is not listed there."
        -- operation, saved keys, spec (nil = All Specs), text, result, reason, key of an accepted add
        local cases = {
            { "add", {}, nil, "abc", nil, NOT_ID },
            { "add", {}, nil, "1.5", nil, NOT_ID },
            { "add", {}, nil, "99999", nil, "No spell has the id 99999." },
            { "add", {}, nil, "23920", 23920, nil, "WARRIOR:23920" },
            { "add", {}, 71, "23920", 23920, nil, "71:23920" },
            { "add", { "WARRIOR:23920" }, nil, "23920", nil, THERE },
            { "add", { "71:23920" }, 71, "23920", nil, THERE },
            { "add", { "WARRIOR:23920" }, 71, "23920", nil, ALL },
            { "add", { "71:23920" }, nil, "23920", 23920, nil, "WARRIOR:23920" },
            { "remove", {}, nil, "abc", nil, NOT_ID },
            { "remove", { "WARRIOR:23920" }, 71, "23920", nil, NOT_THERE },
            { "remove", { "WARRIOR:23920" }, nil, "23920", "WARRIOR:23920", nil },
            { "remove", { "71:23920" }, 71, "23920", "71:23920", nil },
        }
        for i, case in ipairs(cases) do
            local spells = {}
            for _, key in ipairs(case[2]) do spells[key] = { enabled = true } end
            local result, reason
            if case[1] == "add" then
                result, reason = Rules.CanAdd(spells, "WARRIOR", case[3], case[4], nameOf)
            else
                result, reason = Rules.CanRemove(spells, "WARRIOR", case[3], case[4])
            end
            assert.equals(case[5], result, "result, case " .. i)
            assert.equals(case[6], reason, "reason, case " .. i)
            if case[1] == "add" and result then
                assert.equals(case[7], Rules.SpellKey(case[3] or "WARRIOR", result), "key, case " .. i)
            end
        end
    end)

    it("shows the class's All Specs spells and the current spec's, each once, ticked and known", function()
        local function isKnown(id) return id ~= 3 end
        -- saved entries, current spec, expected ids
        local cases = {
            { { ["WARRIOR:20"] = {}, ["71:10"] = {} }, 71, { 10, 20 } },
            { { ["WARRIOR:20"] = {}, ["72:10"] = {}, ["MAGE:30"] = {} }, 71, { 20 } },
            { { ["WARRIOR:20"] = { enabled = false }, ["71:10"] = {} }, 71, { 10 } },
            { { ["WARRIOR:3"] = {}, ["71:10"] = {} }, 71, { 10 } },
            { { ["WARRIOR:20"] = {}, ["71:20"] = {} }, 71, { 20 } },
            { { ["WARRIOR:20"] = { enabled = false }, ["71:20"] = {} }, 71, { 20 } },
            { { ["WARRIOR:20"] = {}, ["71:10"] = {} }, nil, { 20 } },
        }
        for i, case in ipairs(cases) do
            assert.same(case[3], Rules.ResolveList(case[1], "WARRIOR", case[2], isKnown), "case " .. i)
        end
    end)
end)
