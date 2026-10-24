-- Tier 1: the filter a cross-client import runs (Core/ProfileManager.lua,
-- ProfileManager.FilterForClient). It judges each block through the real
-- availability policy, loaded as a baseline or a retail load: a block the
-- client does not run is dropped and named when it was on, retail drops
-- nothing, and a malformed block is refused on both. The payload and the
-- defaults are synthetic; the ids are real (DamageMeter and the CVars owner of
-- the Automation block admitted, PartyBuffs and EnemyCounter withheld).
local helpers = require("dev.spec._helpers")

local function load(baseline)
    -- ProfileManager captures the client's time() at load; the export stamps it.
    _G.time = _G.time or os.time
    local KE = { BASELINE_LOAD = baseline or nil }
    helpers.loadModule("Core/Availability.lua", KE)
    helpers.loadModule("Core/ProfileManager.lua", KE)
    return KE.ProfileManager, KE
end

local DEFAULTS = {
    GlobalFont = "Expressway",
    DamageMeter = { Enabled = false },
    PartyBuffs = { Enabled = false },
    CustomCooldowns = { Enabled = true },
    TotemTracker = { Enabled = false },
    -- A container: Enabled ships true, the feature switches are the real ones.
    KeystoneHelper = { Enabled = true, ResetEnabled = false, RerollEnabled = false, YourKeyEnabled = false },
    Skinning = { Chat = { Enabled = true } },
    Automation = { Enabled = false, CVarsEnabled = true },
    Dungeons = { EnemyCounter = { Enabled = false }, DungeonCasts = { Enabled = false } },
}

local function payload()
    return {
        GlobalFont = "Expressway",
        DamageMeter = { Enabled = true },
        PartyBuffs = { Enabled = true },
        -- Enabled absent: the default, which is on.
        CustomCooldowns = { Spells = {} },
        TotemTracker = { Enabled = false },
        -- Container on, every feature off: not on.
        KeystoneHelper = { Enabled = true },
        Skinning = { Chat = { Enabled = true } },
        Automation = { Enabled = true, alwaysCompareItems = true },
        Dungeons = { EnemyCounter = { Enabled = true }, DungeonCasts = { Enabled = false } },
    }
end

describe("ProfileManager.FilterForClient", function()
    it("keeps core keys and admitted blocks on a baseline load, drops the rest, and names the dropped blocks that were on", function()
        local PM = load(true)
        local profile = payload()
        local dropped = PM.FilterForClient(profile, DEFAULTS)
        assert.equals("Expressway", profile.GlobalFont)
        assert.is_table(profile.DamageMeter)
        assert.is_table(profile.Skinning)
        assert.is_table(profile.Automation)
        assert.is_nil(profile.PartyBuffs)
        assert.is_nil(profile.CustomCooldowns)
        assert.is_nil(profile.TotemTracker)
        -- The container stays, emptied; AceDB refills its sub-blocks.
        assert.same({}, profile.Dungeons)
        assert.is_nil(profile.KeystoneHelper)
        assert.same({ "Custom Cooldowns", "Enemy Counter", "Party Buffs" }, dropped)
        -- The same container with one feature switch on is named.
        assert.same({ "Keystone Helper" }, PM.FilterForClient({ KeystoneHelper = { YourKeyEnabled = true } }, DEFAULTS))
    end)

    it("drops nothing on a retail load", function()
        local PM = load(false)
        local profile = payload()
        local dropped = PM.FilterForClient(profile, DEFAULTS)
        assert.same(payload(), profile)
        assert.same({}, dropped)
    end)

    it("refuses a block keyed by anything but a name, or whose type is not its default's, on either load, without error", function()
        for _, row in ipairs({ { name = "baseline", baseline = true }, { name = "retail", baseline = false } }) do
            local PM = load(row.baseline)
            local profile = {
                [1] = { Enabled = true },
                DamageMeter = true,
                GlobalFont = {},
                Dungeons = { EnemyCounter = "on", [2] = { Enabled = true } },
            }
            local dropped = PM.FilterForClient(profile, DEFAULTS)
            assert.is_nil(profile[1], row.name)
            assert.is_nil(profile.DamageMeter, row.name)
            assert.is_nil(profile.GlobalFont, row.name)
            assert.same({}, profile.Dungeons, row.name)
            assert.same({}, dropped, row.name)
        end
    end)
end)
