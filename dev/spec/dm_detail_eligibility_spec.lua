-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_detail_eligibility_spec.lua                 ║
-- ║  Refusal-rule spec for DamageMeter/Core.lua.             ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Core.lua headlessly (L.loadDMCore) and
-- tests DM:DetailEligible / DM.PlainOwnRow -- the single gate every detail
-- path consults before a breakdown may open or stay open in combat.
--
-- WHY THIS EARNS A SPEC: it is a refusal rule that branches, and both of its
-- failure directions are silent. Too permissive lets a click reach the death
-- recap mid-fight, where an unguarded comparison throws. Too restrictive
-- closes panels that work today, because the tick path that consults it also
-- runs OUT of combat (StopTicker's final paint, OnSessionUpdated's settle
-- repaints). The out-of-combat cases below are not padding -- they are half
-- the contract, and a predicate that forgot the short-circuit would pass a
-- refusals-only suite.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue is a closure over a
-- SECRET table -- values WE declare secret -- and the combat state is a stub.
-- A pass verifies BRANCH ROUTING given declared inputs, never real 12.0 taint
-- semantics. In-game /reload remains the secret-semantics gate.
local L = require("dev.spec._ke_loader")

local SECRET = {}     -- [value] = true  marks a value "secret"
local LOCKDOWN        -- InCombatLockdown() returns this
local AFFECTING       -- UnitAffectingCombat("player") returns this

local DM
local DEATHS, ENEMY, DAMAGE

before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
    LOCKDOWN, AFFECTING = false, false
    DM = L.loadDMCore({
        issecretvalue = function(v) return SECRET[v] == true end,
        InCombatLockdown = function() return LOCKDOWN end,
    })
    -- Not managed by the mock's defaults; DetailCombatActive reads it at
    -- runtime, so it only has to exist by the time a test calls the predicate.
    _G.UnitAffectingCombat = function() return AFFECTING end
    assert(DM and DM.DetailEligible, "loadDMCore did not expose DM.DetailEligible")
    DEATHS = _G.Enum.DamageMeterType.Deaths
    ENEMY  = _G.Enum.DamageMeterType.EnemyDamageTaken
    DAMAGE = _G.Enum.DamageMeterType.DamageDone
end)

describe("PlainOwnRow", function()
    it("resolves true only for boolean true", function()
        assert.is_true(DM.PlainOwnRow(true))
        assert.is_false(DM.PlainOwnRow(false))
        assert.is_false(DM.PlainOwnRow(nil))
        assert.is_false(DM.PlainOwnRow(1))
    end)

    it("resolves a SECRET value to false without comparing it", function()
        local s = {}
        SECRET[s] = true
        assert.is_false(DM.PlainOwnRow(s))
    end)
end)

describe("DetailEligible out of combat", function()
    it("allows a non-own row, Deaths, Enemy Damage Taken, and a nil own-row/meter type", function()
        assert.is_true(DM:DetailEligible(false, DAMAGE))
        assert.is_true(DM:DetailEligible(false, DEATHS))
        assert.is_true(DM:DetailEligible(false, ENEMY))
        assert.is_true(DM:DetailEligible(nil, nil))
    end)
end)

describe("DetailEligible in combat", function()
    before_each(function() LOCKDOWN = true end)

    it("ALLOWS the own row on an ordinary view", function()
        assert.is_true(DM:DetailEligible(true, DAMAGE))
    end)

    it("refuses a non-own row", function()
        assert.is_false(DM:DetailEligible(false, DAMAGE))
    end)

    it("refuses a nil own-row answer", function()
        assert.is_false(DM:DetailEligible(nil, DAMAGE))
    end)

    it("refuses a SECRET own-row value", function()
        local s = {}
        SECRET[s] = true
        assert.is_false(DM:DetailEligible(s, DAMAGE))
    end)

    -- This is the assertion that separates the guarantee from half of it. Deaths
    -- is keyed on a NeverSecret recap id, so every row is addressable; a Deaths
    -- test placed BELOW the own-row rule would open the recap for the player's
    -- own death only and look identical until someone clicked another player's.
    it("ALLOWS the own row, a NON-own row, and a nil own-row answer on Deaths -- identity is not consulted for it", function()
        assert.is_true(DM:DetailEligible(true, DEATHS))
        assert.is_true(DM:DetailEligible(false, DEATHS))
        assert.is_true(DM:DetailEligible(nil, DEATHS))
    end)

    it("refuses the own row on Enemy Damage Taken -- it aggregates across sources", function()
        assert.is_false(DM:DetailEligible(true, ENEMY))
    end)
end)

describe("DetailEligible combat detection", function()
    it("treats a dead player still tagged into the fight as IN combat", function()
        -- InCombatLockdown() drops to false the moment the player dies mid-pull,
        -- but the fight and the API's secrecy continue. Restricting on the union
        -- of both signals can only refuse more often, never less.
        LOCKDOWN, AFFECTING = false, true
        assert.is_false(DM:DetailEligible(false, DAMAGE))
        -- Enemy Damage Taken rather than Deaths: Deaths is now admitted in combat,
        -- so it can no longer show that a view-level refusal fired.
        assert.is_false(DM:DetailEligible(true, ENEMY))
        assert.is_true(DM:DetailEligible(true, DAMAGE))
    end)

    it("is unrestricted only when BOTH signals are clear", function()
        LOCKDOWN, AFFECTING = false, false
        -- A non-own row on an ordinary view: true ONLY because neither signal is
        -- set. Deaths would answer true either way and prove nothing here.
        assert.is_true(DM:DetailEligible(false, DAMAGE))
    end)
end)
