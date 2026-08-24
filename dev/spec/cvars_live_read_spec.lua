-- Tier 1: the live-read refusal only (tiered test policy). What the CVars page
-- does with the answer is frame layout and goes to the in-game smoke; what
-- counts as "no answer" is a guard rule, and this is it.
--
-- The page reads the client rather than its own stored copy. This list is
-- deliberately made of CVars Blizzard does not surface in its own options,
-- which are the ones a patch is most likely to rename, so the read has to
-- survive a CVar that is gone -- both the nil case and the error case. nil is
-- the signal that drops the row entirely, so anything that turns a missing
-- CVar into a number would render a dead control at its own minimum instead.
--
-- FilterLiveDefs is the other half: it is what turns that nil into a row that
-- is never built. It lives on the module rather than inside the page's render
-- closure precisely so it can be reached from here.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local function newFixture(getCVar)
    _G.C_CVar = {
        GetCVar = getCVar,
        SetCVar = function() end,
    }
    _G.SetCVar = _G.C_CVar.SetCVar
    _G.GetCVar = _G.C_CVar.GetCVar
    _G.CreateFrame = function()
        return setmetatable({}, { __index = function() return function() end end })
    end
    _G.hooksecurefunc = function() end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.InCombatLockdown = function() return false end
    _G.issecretvalue = function() return false end
    _G.StaticPopupDialogs = {}
    _G.UIParent = _G.CreateFrame()
    mock.installSpecInfo()

    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/QoL/Automation.lua", { Print = function() end })
    local AU = modules["Automation"]
    AU.RegisterEvent = function() end
    AU.SetEnabledState = function() end
    return AU
end

local BOOL = { key = "someFlag", type = "boolean" }
local NUM = { key = "someNumber", type = "number" }

-- A reader that answers for a named set of CVars and nil for everything else,
-- which is what a client missing a CVar actually looks like.
local function only(present)
    return function(key) return present[key] end
end

describe("live CVar reads", function()
    it("returns nil for a CVar this client does not have", function()
        local AU = newFixture(function() return nil end)
        assert.is_nil(AU:GetLiveCVar(BOOL))
    end)

    it("returns nil rather than erroring when the read itself throws", function()
        local AU = newFixture(function() error("no such cvar") end)
        assert.is_nil(AU:GetLiveCVar(BOOL))
    end)

    it("reads a boolean CVar that is on as true", function()
        local AU = newFixture(function() return "1" end)
        assert.is_true(AU:GetLiveCVar(BOOL))
    end)

    it("reads a boolean CVar that is off as false, not nil", function()
        local AU = newFixture(function() return "0" end)
        assert.is_false(AU:GetLiveCVar(BOOL))
    end)

    it("reads a number CVar as a number", function()
        local AU = newFixture(function() return "3" end)
        assert.equals(3, AU:GetLiveCVar(NUM))
    end)

    -- Zero is a real value for every slider on this page, and `or 0` on a false
    -- reading would make it indistinguishable from absent.
    it("reads a number CVar of zero as zero, not nil", function()
        local AU = newFixture(function() return "0" end)
        assert.equals(0, AU:GetLiveCVar(NUM))
    end)

    it("returns nil for a number CVar holding something that is not a number", function()
        local AU = newFixture(function() return "off" end)
        assert.is_nil(AU:GetLiveCVar(NUM))
    end)
end)

describe("filtering defs by what the client has", function()
    local A = { key = "alpha", type = "boolean" }
    local B = { key = "bravo", type = "boolean" }
    local C = { key = "charlie", type = "boolean" }

    it("drops a def whose CVar this client does not have", function()
        local AU = newFixture(only({ alpha = "1", charlie = "0" }))
        local kept = AU:FilterLiveDefs({ A, B, C })
        assert.equals(2, #kept)
        assert.equals("alpha", kept[1].key)
        assert.equals("charlie", kept[2].key)
    end)

    it("keeps a def whose CVar reads false", function()
        local AU = newFixture(only({ alpha = "0" }))
        local kept = AU:FilterLiveDefs({ A })
        assert.equals(1, #kept)
    end)

    it("returns an empty list when the client has none of them", function()
        local AU = newFixture(only({}))
        assert.equals(0, #AU:FilterLiveDefs({ A, B, C }))
    end)

    it("applies the match predicate as well as the live read", function()
        local AU = newFixture(only({ alpha = "1", bravo = "1", charlie = "1" }))
        local kept = AU:FilterLiveDefs({ A, B, C }, function(def) return def.key ~= "bravo" end)
        assert.equals(2, #kept)
        assert.equals("alpha", kept[1].key)
        assert.equals("charlie", kept[2].key)
    end)

    -- Both halves have to bite, and only a case where each half would produce
    -- a DIFFERENT wrong answer can show it. `alpha` is live but the predicate
    -- rejects it; `bravo` is allowed but the client lacks it; `charlie` passes
    -- both. A filter that ignored the predicate keeps alpha too; one that
    -- ignored the live read keeps bravo too.
    it("keeps only a def that passes the predicate AND the live read", function()
        local AU = newFixture(only({ alpha = "1", charlie = "1" }))
        local kept = AU:FilterLiveDefs({ A, B, C }, function(def) return def.key ~= "alpha" end)
        assert.equals(1, #kept)
        assert.equals("charlie", kept[1].key)
    end)
end)
