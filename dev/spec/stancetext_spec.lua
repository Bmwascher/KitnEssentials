local L = require("dev.spec._ke_loader")

describe("StanceText:EvaluateSpec", function()
    local ST, db, entryForm, entryAura, ctx

    before_each(function()
        ST = L.loadStanceText()
        db = {}
        entryForm = { spellID = 386164, check = "form", options = { 386164, 386196 } }
        entryAura = { spellID = 232698, check = "aura", also = { 194249 } }
        ctx = {
            inCombat = true,
            currentFormSpell = nil,
            hasAura = function() return false end,
            isKnown = function() return true end,
        }
    end)

    it("hides when the spec has no entry", function()
        assert.is_nil(ST:EvaluateSpec(db, 250, nil, ctx))
    end)

    it("hides when that spec is switched off", function()
        db["71Enabled"] = false
        assert.is_nil(ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    it("shows when that spec has never been touched", function()
        assert.equals(386164, ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    it("hides out of combat when combat-only is set", function()
        db["71CombatOnly"] = true
        ctx.inCombat = false
        assert.is_nil(ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    it("hides when the wanted spell is not known", function()
        ctx.isKnown = function() return false end
        assert.is_nil(ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    it("hides when the form is already held", function()
        ctx.currentFormSpell = 386164
        assert.is_nil(ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    it("honours the per-spec required-spell override", function()
        db["71Spell"] = "386196"
        ctx.currentFormSpell = 386164
        assert.equals(386196, ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    it("returns the held form when Reverse Icon is on", function()
        db["71ReverseIcon"] = true
        ctx.currentFormSpell = 386196
        assert.equals(386196, ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    it("counts an alternative aura as satisfied", function()
        ctx.hasAura = function(_, also) return also ~= nil end
        assert.is_nil(ST:EvaluateSpec(db, 258, entryAura, ctx))
    end)
end)
