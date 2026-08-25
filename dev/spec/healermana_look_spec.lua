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

describe("HealerMana:SeedRaidLook", function()
    it("copies a plain value into an absent twin", function()
        local HM = L.loadHealerMana()
        HM.db.IconSize = 30
        HM.db.RaidIconSize = nil
        HM:SeedRaidLook()
        assert.are.equal(30, HM.db.RaidIconSize)
    end)

    it("does not overwrite a twin that already holds a value", function()
        local HM = L.loadHealerMana()
        HM.db.IconSize = 30
        HM.db.RaidIconSize = 48
        HM:SeedRaidLook()
        assert.are.equal(48, HM.db.RaidIconSize)
    end)

    it("copies colour tables by value, not by reference", function()
        -- Sharing the table would make the two modes the same setting wearing
        -- two names: editing Raid's colour would silently change Dungeon's.
        local HM = L.loadHealerMana()
        HM.db.HighManaColor = { 1, 0, 0, 1 }
        HM.db.RaidHighManaColor = nil
        HM:SeedRaidLook()
        HM.db.RaidHighManaColor[1] = 0
        assert.are.equal(1, HM.db.HighManaColor[1])
    end)

    it("covers every key the accessor can resolve", function()
        -- Asserted against an INDEPENDENT list, not HM.LOOK_KEYS. Walking the
        -- same list the implementation walks is a tautology: a key dropped
        -- from LOOK_KEYS would vanish from both loops and still pass.
        local EXPECTED = {
            "FrameWidth", "IconSize", "IconType",
            "NameFontSize", "NameXOffset", "NameYOffset",
            "ManaFontSize", "ManaXOffset", "ManaYOffset",
            "FontOutline", "HighManaColor",
            "GrowDirection", "FrameSpacing",
        }
        local HM = L.loadHealerMana()
        HM:SeedRaidLook()
        for _, key in ipairs(EXPECTED) do
            assert.is_not_nil(HM.db["Raid" .. key], key .. " was not seeded")
        end
        assert.are.equal(#EXPECTED, #HM.LOOK_KEYS)
    end)
end)

describe("HealerMana:FindHealers preview ownership", function()
    it("leaves an open preview's healer list alone", function()
        -- A refusal rule: roster, zone and spec events all reach FindHealers,
        -- and replacing the canned rows there left the page editing Raid while
        -- the frame drew Dungeon.
        local HM, KE = L.loadHealerMana({ IsInRaid = function() return false end })
        KE.PreviewManager = { IsPreviewActive = function() return true end }
        HM.isPreview = true
        HM.currentHealers = { { unit = "player", name = "sentinel" } }
        HM:FindHealers()
        assert.are.equal(1, #HM.currentHealers)
        assert.are.equal("sentinel", HM.currentHealers[1].name)
        assert.is_true(HM.isPreview)
    end)

    it("heals an orphaned flag when no preview owner is live", function()
        -- The manager's per-module cache can read "hidden" while the flag is
        -- still set, and StopAllPreviews skips anything already cached hidden.
        -- Obeying the flag then strands fabricated rows on screen for good.
        local HM, KE = L.loadHealerMana({ IsInRaid = function() return false end })
        KE.PreviewManager = { IsPreviewActive = function() return false end }
        HM.isPreview = true
        HM.currentHealers = { { unit = "player", name = "sentinel" } }
        HM:FindHealers()
        assert.is_false(HM.isPreview)
        assert.are.equal(0, #HM.currentHealers)
    end)
end)
