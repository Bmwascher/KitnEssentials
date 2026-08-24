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

local writes

local function newFixture(getCVar)
    writes = {}
    _G.C_CVar = {
        GetCVar = getCVar,
        SetCVar = function(key, value) writes[#writes + 1] = { key, value } end,
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


-- The other half of the same refusal. Dropping the ROW keeps a dead control off
-- the page; dropping the WRITE keeps SetCVar off a name this client does not
-- have, which is an error rather than a no-op. A stored value outliving its
-- CVar is not hypothetical: a profile written on a client that had it, or a
-- patch that renames one, both produce it.
describe("applying settings for a CVar the client lacks", function()
    local BOOLDEF = { key = "someFlag", type = "boolean" }
    local NUMDEF = { key = "someNumber", type = "number" }

    local function applyWith(getCVar, defs, sliderDefs, db)
        local AU = newFixture(getCVar)
        AU.CVAR_DEFS = defs or {}
        AU.CVAR_SLIDER_DEFS = sliderDefs or {}
        AU.db = db or {}
        AU.db.CVarsEnabled = true
        AU:ApplyCVars()
        return AU
    end

    local function wroteKeys()
        local keys = {}
        for i = 1, #writes do keys[#keys + 1] = writes[i][1] end
        return table.concat(keys, ",")
    end

    it("writes nothing for an absent boolean the profile still has a value for", function()
        applyWith(function() return nil end, { BOOLDEF }, nil, { someFlag = true })
        assert.equals("", wroteKeys())
    end)

    it("writes nothing for an absent slider the profile still has a value for", function()
        applyWith(function() return nil end, nil, { NUMDEF }, { someNumber = 3 })
        assert.equals("", wroteKeys())
    end)

    -- The control. Without it the two cases above also pass on a build that
    -- writes nothing ever.
    it("still writes a present CVar whose stored value differs", function()
        applyWith(only({ someFlag = "0" }), { BOOLDEF }, nil, { someFlag = true })
        assert.equals("someFlag", wroteKeys())
    end)

    it("still writes a present slider whose stored value differs", function()
        applyWith(only({ someNumber = "1" }), nil, { NUMDEF }, { someNumber = 3 })
        assert.equals("someNumber", wroteKeys())
    end)

    -- An absent primary takes its companion with it: a master flag is worth
    -- nothing when the mode it serves is gone, and writing it is the same
    -- error on a different name.
    it("writes no companion for an absent primary", function()
        local def = { key = "someFlag", type = "boolean", companion = "someMaster" }
        applyWith(function() return nil end, { def }, nil, { someFlag = true })
        assert.equals("", wroteKeys())
    end)

    -- The stored copy must not gain a value the client cannot back. 0 is a real
    -- setting for every slider on this page, so inventing it is what made the
    -- write happen in the first place.
    it("stores nil rather than zero when a slider CVar is absent", function()
        local AU = newFixture(function() return nil end)
        AU.CVAR_DEFS = {}
        AU.CVAR_SLIDER_DEFS = { NUMDEF }
        AU.db = {}
        AU:SyncFromCVars()
        assert.is_nil(AU.db.someNumber)
    end)

    -- The boolean half of the same rule. A raw read makes an absent boolean
    -- `false`, which is a real setting rather than an absence.
    it("stores nil rather than false when a boolean CVar is absent", function()
        local AU = newFixture(function() return nil end)
        AU.CVAR_DEFS = { BOOLDEF }
        AU.CVAR_SLIDER_DEFS = {}
        AU.db = {}
        AU:SyncFromCVars()
        assert.is_nil(AU.db.someFlag)
    end)

    -- The control: a present CVar still gets stored, and stored as its value.
    it("still stores a present boolean that reads false", function()
        local AU = newFixture(only({ someFlag = "0" }))
        AU.CVAR_DEFS = { BOOLDEF }
        AU.CVAR_SLIDER_DEFS = {}
        AU.db = {}
        AU:SyncFromCVars()
        assert.is_false(AU.db.someFlag)
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
