local L = require("dev.spec._ke_loader")

local BURNING_RUSH = 111400

-- An overlay stub that answers only for Burning Rush, so a case cannot pass by
-- accident on some other spell's glow.
local function overlaySaying(on)
    return { IsSpellOverlayed = function(spellID) return spellID == BURNING_RUSH and on or false end }
end

describe("BurningRush seed state", function()
    it("turns on when the activation overlay says the spell is glowing", function()
        local BURN, rec = L.loadBurningRush({ overlay = overlaySaying(true) })
        BURN:RefreshActiveState()
        assert.same({ true }, rec.setActive)
    end)

    it("turns off on the overlay even when a readable aura disagrees", function()
        -- The aura is deliberately PRESENT and contradicts the overlay. Without
        -- that contradiction this case cannot tell overlay-first from
        -- aura-first: both orderings would produce the same answer.
        local BURN, rec = L.loadBurningRush({
            overlay = overlaySaying(false), aura = { spellId = BURNING_RUSH }, active = true,
        })
        BURN:RefreshActiveState()
        assert.same({ false }, rec.setActive)
    end)

    it("does not repaint when the overlay agrees with the current state", function()
        local BURN, rec = L.loadBurningRush({ overlay = overlaySaying(false), active = false })
        BURN:RefreshActiveState()
        assert.same({}, rec.setActive)
    end)

    it("REFUSES to decide when there is no overlay and identities are hidden", function()
        -- The whole point of the wave. The aura read would return nothing here
        -- and the old code read that as "not running", switching off a warning
        -- about an active health drain.
        local BURN, rec = L.loadBurningRush({ overlay = nil, aura = nil, active = true, aurasHidden = true })
        BURN:RefreshActiveState()
        assert.same({}, rec.setActive)
        assert.is_true(BURN.active)
    end)

    it("falls back to the aura when there is no overlay and identities are readable", function()
        local BURN, rec = L.loadBurningRush({ overlay = nil, aura = { spellId = BURNING_RUSH } })
        BURN:RefreshActiveState()
        assert.same({ true }, rec.setActive)
    end)

    it("turns off from a readable aura that is absent", function()
        local BURN, rec = L.loadBurningRush({ overlay = nil, aura = nil, active = true })
        BURN:RefreshActiveState()
        assert.same({ false }, rec.setActive)
    end)

    it("does nothing at all while the preview owns the frame", function()
        local BURN, rec = L.loadBurningRush({ overlay = overlaySaying(true), isPreview = true })
        BURN:RefreshActiveState()
        assert.same({}, rec.setActive)
    end)
end)
