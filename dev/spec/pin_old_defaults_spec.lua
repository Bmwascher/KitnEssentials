-- Tier 1: the old-default pins for Healer Mana and CC Tracker (Core/Defaults.lua,
-- PinOldDefaults). Both modules shipped with other defaults. A key absent from
-- the saved variables sat at its OLD default, because the build that wrote the
-- file stripped default-equal leaves at logout. A profile that already holds
-- the block gets that old value written back; any key the player set is left
-- alone; a profile without the block, a profile made after the first run and an
-- import all take the new defaults. CC Tracker's pin holds its position only:
-- its retired Max Enemies is deleted, set or not.
local helpers = require("dev.spec._helpers")

local function migrate(sv)
    _G.KitnEssentialsDB = sv
    local KE = helpers.loadModule("Core/Defaults.lua")
    KE:MigrateCombatLoggerKeys()
    return _G.KitnEssentialsDB, KE
end

local function healerMana(profile)
    return profile.Dungeons and profile.Dungeons.HealerMana
end

describe("old-default pins", function()
    after_each(function()
        _G.KitnEssentialsDB = nil
    end)

    it("writes the old value of every unset changed key into an existing block", function()
        local sv = migrate({ profiles = { Default = {
            Dungeons = { HealerMana = { Enabled = true } },
            CCTracker = { Enabled = true },
        } } })
        local hm = healerMana(sv.profiles.Default)
        assert.is_false(hm.DisableOnHealer)
        assert.are.equal(-400, hm.Position.XOffset)
        local cc = sv.profiles.Default.CCTracker
        assert.is_nil(cc.MaxEnemies)
        assert.are.same({ YOffset = 69 }, cc.Position)
    end)

    it("keeps every value the player set but the retired Max Enemies, a partly saved position included", function()
        local sv = migrate({ profiles = { Default = {
            Dungeons = { HealerMana = {
                DisableOnHealer = true,
                anchorFrameType = "SELECTFRAME",
                ParentFrame = "ERFPartyHeader",
                Position = { XOffset = 12, YOffset = -30 },
                IconSize = 38,
            } },
            CCTracker = { MaxEnemies = 5, Position = { YOffset = 59 } },
        } } })
        local hm = healerMana(sv.profiles.Default)
        assert.is_true(hm.DisableOnHealer)
        assert.are.equal("SELECTFRAME", hm.anchorFrameType)
        assert.are.equal("ERFPartyHeader", hm.ParentFrame)
        assert.are.same({ AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 12, YOffset = -30 }, hm.Position)
        assert.are.equal(38, hm.IconSize)
        assert.are.equal(14, hm.NameFontSize)
        local cc = sv.profiles.Default.CCTracker
        assert.is_nil(cc.MaxEnemies)
        assert.are.equal(59, cc.Position.YOffset)
    end)

    it("creates no block in a profile that never had one", function()
        local sv = migrate({ profiles = { Default = { Dungeons = { DeathNotifications = {} } } } })
        assert.is_nil(sv.profiles.Default.Dungeons.HealerMana)
        assert.is_nil(sv.profiles.Default.CCTracker)
    end)

    it("leaves a profile made after the first run on the new defaults", function()
        local sv = migrate({ profiles = { Default = {} } })
        sv.profiles.Later = { Dungeons = { HealerMana = { Enabled = true } }, CCTracker = { Enabled = true } }
        local KE = helpers.loadModule("Core/Defaults.lua")
        KE:MigrateCombatLoggerKeys()
        local later = _G.KitnEssentialsDB.profiles.Later
        assert.is_nil(healerMana(later).IconSize)
        assert.is_nil(later.CCTracker.MaxEnemies)
    end)

    it("leaves an import on the new defaults", function()
        local _, KE = migrate(nil)
        local profile = { Dungeons = { HealerMana = { Enabled = true } }, CCTracker = { Enabled = true } }
        KE:MigrateProfileKeys(profile)
        assert.are.same({ Enabled = true }, healerMana(profile))
        assert.are.same({ Enabled = true }, profile.CCTracker)
    end)
end)
