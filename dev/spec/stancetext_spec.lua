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
            auraIdentityVisible = function() return true end,
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

    it("honors the per-spec required-spell override", function()
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
        assert.is_nil(ST:EvaluateSpec(db, 65, entryAura, ctx))
    end)

    -- Shadowform reads as a form, so Voidform has to satisfy it on the form
    -- path or a priest mid-Voidform gets accused of being out of Shadowform.
    it("counts an alternative form as satisfied", function()
        ctx.currentFormSpell = 194249
        assert.is_nil(ST:EvaluateSpec(db, 258, ST.SPECS[258], ctx))
    end)

    -- Restricted content hides aura identity, so "not found" stops meaning
    -- "not present". Accusing on it is the bug this guard exists to prevent.
    it("stays quiet when aura identity is hidden", function()
        ctx.auraIdentityVisible = function() return false end
        assert.is_nil(ST:EvaluateSpec(db, 258, entryAura, ctx))
    end)

    -- The guard is scoped to aura checks. A stance is read through a different
    -- subsystem that restricted content never touches, so it must still alert.
    it("does not let hidden aura identity silence a form check", function()
        ctx.auraIdentityVisible = function() return false end
        assert.equals(386164, ST:EvaluateSpec(db, 71, entryForm, ctx))
    end)

    -- Forever's Required dropdown: 0 is no requirement, -1 any of the options.
    it("hides with no requirement, whatever the form", function()
        local entryNone = { spellID = 0, check = "form", options = { 0, 386164 } }
        assert.is_nil(ST:EvaluateSpec(db, 71, entryNone, ctx))
        ctx.currentFormSpell = 386164
        assert.is_nil(ST:EvaluateSpec(db, 71, entryNone, ctx))
    end)

    it("under any, hides while a form is up and otherwise draws the first known option", function()
        local entryAny = { spellID = -1, check = "form", options = { -1, 0, 101, 102 } }
        ctx.isKnown = function(id) return id ~= 101 end
        assert.equals(102, ST:EvaluateSpec(db, 65, entryAny, ctx))
        ctx.currentFormSpell = 999
        assert.is_nil(ST:EvaluateSpec(db, 65, entryAny, ctx))
    end)

    it("under any, hides when no option is known", function()
        local entryAny = { spellID = -1, check = "form", options = { -1, 0, 101, 102 } }
        ctx.isKnown = function(id) return id <= 0 end
        assert.is_nil(ST:EvaluateSpec(db, 65, entryAny, ctx))
    end)

    -- A higher rank of the wanted form is the wanted form.
    it("counts a form the context matches to the wanted spell as satisfied", function()
        local entryBear = { spellID = 5487, check = "form" }
        ctx.currentFormSpell = 9634
        ctx.sameSpell = function(a, b) return a == 9634 and b == 5487 end
        assert.is_nil(ST:EvaluateSpec(db, 1484, entryBear, ctx))
    end)
end)
