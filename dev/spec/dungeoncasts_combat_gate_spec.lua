-- IsValidUnit's Combat Only refusal rule: a guard, not a throws case --
-- UnitAffectingCombat's return is non-nilable, so this only ever refuses on
-- an explicit false.

local L = require("dev.spec._ke_loader")

local function load(opts)
    opts = opts or {}
    return L.loadDungeonCasts({ UnitAffectingCombat = opts.combat })
end

describe("DungeonCasts Combat Only gate", function()
    it("refuses a unit that is not affecting combat when the flag is on", function()
        local DC = load({ combat = function() return false end })
        DC.db = { Frame = { CombatOnly = true } }
        assert.is_false(DC:IsValidUnit("nameplate1"))
    end)

    it("allows a unit that is affecting combat when the flag is on", function()
        local DC = load({ combat = function() return true end })
        DC.db = { Frame = { CombatOnly = true } }
        assert.is_true(DC:IsValidUnit("nameplate1"))
    end)

    it("allows a unit out of combat when the flag is off", function()
        local DC = load({ combat = function() return false end })
        DC.db = { Frame = { CombatOnly = false } }
        assert.is_true(DC:IsValidUnit("nameplate1"))
    end)
end)

-- The rescan exists to collect mobs Combat Only refused mid-cast. With the
-- flag off nothing was ever refused, so running it anyway is not a no-op: it
-- surfaces units MaxBars turned away on an earlier pull.
describe("DungeonCasts combat-start rescan", function()
    local function loadWithSpy(combatOnly)
        local DC = load()
        DC.db = { Frame = { CombatOnly = combatOnly } }
        DC.instanceActive = true
        DC.isPreview = false
        local scanned = false
        DC.ScanExistingNameplates = function() scanned = true end
        return DC, function() return scanned end
    end

    it("rescans on a pull while the flag is on", function()
        local DC, wasScanned = loadWithSpy(true)
        DC:OnCombatStart()
        assert.is_true(wasScanned())
    end)

    it("does not rescan while the flag is off", function()
        local DC, wasScanned = loadWithSpy(false)
        DC:OnCombatStart()
        assert.is_false(wasScanned())
    end)
end)

-- A held bar carries the interrupt colour under "Interrupted by X". An
-- interruptible event arriving after a refused cast start would repaint it to
-- a live cast colour and contradict its own text.
describe("DungeonCasts interrupt hold vs interruptible repaint", function()
    local function loadWithBar(holdUntil)
        local DC = L.loadDungeonCasts({
            C_CastingInfo = {
                GetCastInfo = function() return { notInterruptible = false } end,
                GetChannelInfo = function() return nil end,
            },
        })
        local repainted = false
        DC.UpdateBarColor = function() repainted = true end
        DC.activeFrames = { nameplate1 = { holdUntil = holdUntil } }
        return DC, function() return repainted end
    end

    it("repaints a bar that is not holding", function()
        local DC, wasRepainted = loadWithBar(nil)
        DC:UpdateInterruptible("nameplate1")
        assert.is_true(wasRepainted())
    end)

    it("leaves a held bar alone", function()
        local DC, wasRepainted = loadWithBar(999)
        DC:UpdateInterruptible("nameplate1")
        assert.is_false(wasRepainted())
    end)
end)
