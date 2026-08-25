-- Tier 2: which of two values a setting resolves to is invented branching
-- logic with a silent failure mode -- the wrong one renders a plausible frame
-- at the wrong size. The preview case is the one a later edit breaks: the GUI
-- must be able to show Raid sizes while the player stands alone in a party.
local L = require("dev.spec._ke_loader")

describe("HealerMana:Look", function()
    local function raidSplit()
        local HM = L.loadHealerMana({ IsInRaid = function() return true end })
        HM.db.SplitPositioning = true
        HM.db.RaidIconSize = 48
        HM:RefreshMode()
        return HM
    end

    it("returns the raid twin when split is on and raid is live", function()
        assert.are.equal(48, raidSplit():Look("IconSize"))
    end)

    it("returns the plain key when the split is off", function()
        local HM = raidSplit()
        HM.db.SplitPositioning = false
        assert.are.equal(24, HM:Look("IconSize"))
    end)

    it("returns the plain key in dungeon mode even with a twin set", function()
        local HM = raidSplit()
        HM.db.EnableInRaid = false
        HM:RefreshMode()
        assert.are.equal(24, HM:Look("IconSize"))
    end)

    it("falls through to the plain key when the twin is nil", function()
        local HM = raidSplit()
        HM.db.RaidIconSize = nil
        assert.are.equal(24, HM:Look("IconSize"))
    end)

    it("honours the preview context over the live mode", function()
        local HM = L.loadHealerMana({ IsInRaid = function() return false end })
        HM.db.SplitPositioning = true
        HM.db.RaidIconSize = 48
        HM:RefreshMode()
        assert.are.equal(24, HM:Look("IconSize"))
        HM.isPreview = true
        HM.previewContext = "RAID"
        assert.are.equal(48, HM:Look("IconSize"))
    end)

    it("returns a twin holding false rather than falling through", function()
        -- `false` is a legitimate stored value, not an absent one. A `v or`
        -- fallthrough would silently ignore it; only nil may fall through.
        local HM = raidSplit()
        HM.db.RaidGrowDirection = false
        assert.are.equal(false, HM:Look("GrowDirection"))
    end)
end)
