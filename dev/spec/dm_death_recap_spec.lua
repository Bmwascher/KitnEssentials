-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_death_recap_spec.lua                        ║
-- ║  Return-shape spec for DM:GetDeathRecap.                 ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Core.lua headlessly (L.loadDMCore) and
-- tests the fetch three surfaces depend on: the click preflight, the panel
-- renderer and the hover tip. All three branch on WHICH of three shapes came
-- back, so the shapes are the contract.
--
--   success     (events, sinkMax, plainMax)
--   absent      (nil, nil, nil)
--   unreadable  (nil, DM.RECAP_UNREADABLE, nil)
--
-- WHY THIS EARNS A SPEC: every branch here is a refusal rule or a guard whose
-- failure is silent. Reading "we did not get an answer" as "no recap" hides a
-- recap that exists. Letting a plain zero maximum through draws an empty red
-- bar that asserts the player died at full health. Confusing the absent and
-- unreadable shapes shows the wrong message, which is the one thing that
-- tells us in game whether the recap is reachable in combat at all.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue and canaccesstable are
-- stubs, and secrecy is whatever this file declares. A pass verifies BRANCH
-- ROUTING given declared inputs, never real 12.0 taint semantics. In-game
-- /reload remains the secret-semantics gate.
local L = require("dev.spec._ke_loader")

local SECRET = {}     -- [value] = true  marks a value "secret"
local DM

-- Build a C_DeathRecap stub and load Core.lua against it. C_DeathRecap is
-- captured as a file-scope local at load time, so it has to exist BEFORE the
-- loader runs -- reassigning _G afterwards would not be seen.
--   events   : what GetRecapEvents returns (a function is called instead)
--   maxHealth: what GetRecapMaxHealth returns (a function is called instead)
--   has      : what HasRecapEvents returns (a function is called instead)
local function load(api)
    api = api or {}
    if api.absentAPI then
        _G.C_DeathRecap = nil
    else
        _G.C_DeathRecap = {
            GetRecapEvents = function()
                if type(api.events) == "function" then return api.events() end
                return api.events
            end,
        }
        if api.maxHealth ~= nil then
            _G.C_DeathRecap.GetRecapMaxHealth = function()
                if type(api.maxHealth) == "function" then return api.maxHealth() end
                return api.maxHealth
            end
        end
        if api.has ~= nil then
            _G.C_DeathRecap.HasRecapEvents = function()
                if type(api.has) == "function" then return api.has() end
                return api.has
            end
        end
    end
    DM = L.loadDMCore({
        issecretvalue = function(v) return SECRET[v] == true end,
    })
    -- Read as a global at call time, so this may be set after the load.
    _G.canaccesstable = function() return api.canaccess ~= false end
    assert(DM and DM.GetDeathRecap, "loadDMCore did not expose DM.GetDeathRecap")
end

before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
end)

describe("GetDeathRecap entry guards", function()
    it("returns the ABSENT shape when C_DeathRecap is missing", function()
        load({ absentAPI = true })
        local ev, reason, plain = DM:GetDeathRecap(1)
        assert.is_nil(ev); assert.is_nil(reason); assert.is_nil(plain)
    end)

    it("returns the ABSENT shape for a nil recap id", function()
        load({ events = { {} } })
        local ev, reason = DM:GetDeathRecap(nil)
        assert.is_nil(ev); assert.is_nil(reason)
    end)

    it("returns the ABSENT shape for a SECRET recap id, without comparing it", function()
        SECRET[7] = true
        load({ events = { {} } })
        local ev, reason = DM:GetDeathRecap(7)
        assert.is_nil(ev); assert.is_nil(reason)
    end)

    it("returns the ABSENT shape for a non-positive recap id", function()
        load({ events = { {} } })
        local ev, reason = DM:GetDeathRecap(0)
        assert.is_nil(ev); assert.is_nil(reason)
        ev, reason = DM:GetDeathRecap(-3)
        assert.is_nil(ev); assert.is_nil(reason)
    end)
end)

describe("GetDeathRecap HasRecapEvents preflight", function()
    it("refuses ONLY on a proven-plain false, and gives no reason", function()
        load({ has = false, events = { {} } })
        local ev, reason = DM:GetDeathRecap(1)
        assert.is_nil(ev); assert.is_nil(reason)
    end)

    it("falls through on a SECRET answer and returns the recap", function()
        local s = { __tag = "secret-bool" }
        SECRET[s] = true
        load({ has = s, events = { { id = 1 } } })
        local ev = DM:GetDeathRecap(1)
        assert.is_table(ev)
        assert.equals(1, #ev)
    end)

    it("falls through on a FAILED call and returns the recap", function()
        load({ has = function() error("blocked") end, events = { { id = 1 } } })
        local ev = DM:GetDeathRecap(1)
        assert.is_table(ev)
        assert.equals(1, #ev)
    end)

    it("falls through when the preflight does not exist at all", function()
        load({ events = { { id = 1 } } })
        local ev = DM:GetDeathRecap(1)
        assert.is_table(ev)
    end)
end)

describe("GetDeathRecap container accessibility", function()
    it("returns the UNREADABLE shape, and no events, when the container is unindexable", function()
        load({ canaccess = false, events = { { id = 1 }, { id = 2 } } })
        local ev, reason, plain = DM:GetDeathRecap(1)
        -- Two events were available and none came back: the refusal happened
        -- before the reversal, not after it.
        assert.is_nil(ev)
        assert.equals(DM.RECAP_UNREADABLE, reason)
        assert.is_nil(plain)
    end)

    it("proceeds when the predicate does not exist on this client", function()
        load({ events = { { id = 1 } } })
        _G.canaccesstable = nil
        local ev = DM:GetDeathRecap(1)
        assert.is_table(ev)
    end)

    it("returns the ABSENT shape for a failed fetch and for an empty list", function()
        load({ events = function() error("blocked") end })
        local ev, reason = DM:GetDeathRecap(1)
        assert.is_nil(ev); assert.is_nil(reason)

        load({ events = {} })
        ev, reason = DM:GetDeathRecap(1)
        assert.is_nil(ev); assert.is_nil(reason)
    end)
end)

describe("GetDeathRecap event order", function()
    it("reverses the API's newest-first list to oldest-first, keeping every event", function()
        -- The API returns most-recent-first, so the LAST element of the result
        -- is the killing blow -- which is what the fatal marker and the death
        -- timestamp both key on.
        load({ events = { { id = "newest" }, { id = "middle" }, { id = "oldest" } } })
        local ev = DM:GetDeathRecap(1)
        assert.equals(3, #ev)
        assert.equals("oldest", ev[1].id)
        assert.equals("middle", ev[2].id)
        assert.equals("newest", ev[3].id)
    end)
end)

describe("GetDeathRecap maximum health", function()
    it("passes a SECRET maximum to the sink return and leaves the plain one nil", function()
        local s = { __tag = "secret-hp" }
        SECRET[s] = true
        load({ events = { { id = 1 } }, maxHealth = s })
        local ev, sinkMax, plainMax = DM:GetDeathRecap(1)
        assert.is_table(ev)
        assert.equals(s, sinkMax)
        assert.is_nil(plainMax)
    end)

    it("populates BOTH returns from a plain positive maximum", function()
        load({ events = { { id = 1 } }, maxHealth = 5000 })
        local _, sinkMax, plainMax = DM:GetDeathRecap(1)
        assert.equals(5000, sinkMax)
        assert.equals(5000, plainMax)
    end)

    -- Both returns, every time. Asserting only the plain one would let a zero
    -- reach the bar, which draws an empty red row -- a claim that the player
    -- died at full health.
    it("leaves BOTH returns nil for a zero maximum", function()
        load({ events = { { id = 1 } }, maxHealth = 0 })
        local _, sinkMax, plainMax = DM:GetDeathRecap(1)
        assert.is_nil(sinkMax); assert.is_nil(plainMax)
    end)

    it("leaves BOTH returns nil for a negative maximum", function()
        load({ events = { { id = 1 } }, maxHealth = -1 })
        local _, sinkMax, plainMax = DM:GetDeathRecap(1)
        assert.is_nil(sinkMax); assert.is_nil(plainMax)
    end)

    it("leaves BOTH returns nil for a non-numeric maximum", function()
        load({ events = { { id = 1 } }, maxHealth = "lots" })
        local _, sinkMax, plainMax = DM:GetDeathRecap(1)
        assert.is_nil(sinkMax); assert.is_nil(plainMax)
    end)

    it("leaves BOTH returns nil for a FAILED maximum call", function()
        load({ events = { { id = 1 } }, maxHealth = function() error("blocked") end })
        local ev, sinkMax, plainMax = DM:GetDeathRecap(1)
        assert.is_table(ev)
        assert.is_nil(sinkMax); assert.is_nil(plainMax)
    end)

    it("leaves BOTH returns nil when the maximum accessor does not exist", function()
        load({ events = { { id = 1 } } })
        local ev, sinkMax, plainMax = DM:GetDeathRecap(1)
        assert.is_table(ev)
        assert.is_nil(sinkMax); assert.is_nil(plainMax)
    end)
end)
