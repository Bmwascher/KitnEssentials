-- Tier 1: the skin tint decision. KE:GetSkinBrandColor resolves accent vs
-- neutral off Theme.TintSkins, and KE:SetTintSkins / KE:ResetTheme decide
-- whether that resolution moved far enough to warrant a reload prompt. A
-- wrong resolution mistints every skinned Blizzard frame built after it; a
-- wrong reload decision either nags on every ordinary preset change or
-- silently leaves stale frames tinted after a real flip.
local L = require("dev.spec._ke_loader")

describe("KE skin tint decision", function()
    local KE, refreshCalls, flagCalls

    before_each(function()
        KE = L.loadAddonTheme()
        refreshCalls, flagCalls = 0, 0
        -- Replaced AFTER the load: AddonTheme.lua defines RefreshTheme
        -- itself, and this file only cares whether SetTintSkins/ResetTheme
        -- call it, not what it actually refreshes. FlagReloadNeeded lives
        -- outside this file entirely, so it needs a stub either way.
        KE.RefreshTheme = function() refreshCalls = refreshCalls + 1 end
        KE.FlagReloadNeeded = function() flagCalls = flagCalls + 1 end
    end)

    it("resolves to the accent when TintSkins is true", function()
        KE.db = { global = { Theme = {
            Mode = "custom", Custom = { accent = { 0.2, 0.4, 0.6, 1 } }, TintSkins = true,
        } } }
        assert.same(KE:GetThemeColor("accent"), KE:GetSkinBrandColor())
    end)

    it("resolves to the neutral when TintSkins is false, whatever the accent is", function()
        for _, accent in ipairs({ { 0.2, 0.4, 0.6, 1 }, { 0.9, 0.1, 0.3, 1 } }) do
            KE.db = { global = { Theme = {
                Mode = "custom", Custom = { accent = accent }, TintSkins = false,
            } } }
            assert.same(KE.SkinNeutralColor, KE:GetSkinBrandColor())
        end
    end)

    -- The upgrade path for a profile saved before TintSkins existed: it has
    -- no key at all, and a default that silently flipped to false would
    -- mistint every such profile without anyone touching the setting.
    it("resolves to the accent when TintSkins is absent", function()
        KE.db = { global = { Theme = {
            Mode = "custom", Custom = { accent = { 0.2, 0.4, 0.6, 1 } },
        } } }
        assert.same(KE:GetThemeColor("accent"), KE:GetSkinBrandColor())
    end)

    it("SetTintSkins flags a reload when the resolved colour moves", function()
        KE.db = { global = { Theme = {
            Mode = "custom", Custom = { accent = { 0.2, 0.4, 0.6, 1 } }, TintSkins = true,
        } } }
        KE:SetTintSkins(false)
        assert.equals(1, flagCalls)
        assert.equals(1, refreshCalls)
    end)

    it("SetTintSkins does not flag a reload when the colour does not move", function()
        -- Custom accent set equal to the neutral, so on and off resolve
        -- identically -- the switch itself still has to run through.
        local sameAsNeutral = {
            KE.SkinNeutralColor[1], KE.SkinNeutralColor[2],
            KE.SkinNeutralColor[3], KE.SkinNeutralColor[4],
        }
        KE.db = { global = { Theme = {
            Mode = "custom", Custom = { accent = sameAsNeutral }, TintSkins = true,
        } } }
        KE:SetTintSkins(false)
        assert.equals(0, flagCalls)
        assert.equals(1, refreshCalls)
    end)

    it("ResetTheme flags a reload only when it starts with tint off", function()
        -- From tint OFF: the reset restores the default ON, and the resolved
        -- colour actually moves (neutral -> preset accent), so this must
        -- flag.
        KE.db = { global = { Theme = {
            Mode = "custom", Custom = { accent = { 0.2, 0.4, 0.6, 1 } }, TintSkins = false,
        } } }
        KE:ResetTheme()
        assert.equals(1, flagCalls)

        -- From tint already ON: reset still moves the accent by restoring
        -- the preset, but the tint decision itself never changed, so this
        -- must NOT flag -- the negative half that catches a reset which
        -- starts prompting on every ordinary preset restore.
        flagCalls = 0
        KE.db = { global = { Theme = {
            Mode = "custom", Custom = { accent = { 0.9, 0.1, 0.3, 1 } }, TintSkins = true,
        } } }
        KE:ResetTheme()
        assert.equals(0, flagCalls)
        assert.equals(2, refreshCalls)
    end)
end)
