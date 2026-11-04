-- Tier 1: the filter a cross-client import runs (Core/ProfileManager.lua,
-- ProfileManager.FilterForClient). It judges each block through the real
-- availability policy, loaded as a baseline or a retail load: a block the
-- client does not run is dropped and named when it was on, retail drops
-- nothing but Forever-only blocks, and a malformed block is refused on both.
-- The payload and the defaults are synthetic; the ids are real (DamageMeter,
-- KeystoneHelper, the CVars owner of the Automation block and the Dungeons
-- sub-blocks EnemyCounter and DungeonCasts admitted; PartyBuffs and
-- HuntersMark, the top-level block that was on by default, withheld).
-- VantusRune is the withheld block that was off: its runes are retail items,
-- so Forever never admits it. Dungeons.DungeonTimers is a made-up sub-block
-- under a real id that Forever never admits, so the nested drop holds
-- whatever other Dungeons modules are admitted.
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
    HuntersMark = { Enabled = true },
    VantusRune = { Enabled = false },
    -- A container: Enabled ships true, the feature switches are the real ones.
    KeystoneHelper = { Enabled = true, ResetEnabled = false, RerollEnabled = false, YourKeyEnabled = false },
    Skinning = { Chat = { Enabled = true } },
    Automation = { Enabled = false, CVarsEnabled = true },
    Dungeons = { EnemyCounter = { Enabled = false }, DungeonCasts = { Enabled = false }, DungeonTimers = { Enabled = false } },
}

local function payload()
    return {
        GlobalFont = "Expressway",
        DamageMeter = { Enabled = true },
        PartyBuffs = { Enabled = true },
        -- Enabled absent: the default, which is on.
        HuntersMark = { Scale = 1 },
        VantusRune = { Enabled = false },
        -- Container on, every feature off: not on.
        KeystoneHelper = { Enabled = true },
        Skinning = { Chat = { Enabled = true } },
        Automation = { Enabled = true, alwaysCompareItems = true },
        Dungeons = { EnemyCounter = { Enabled = true }, DungeonCasts = { Enabled = false }, DungeonTimers = { Enabled = true } },
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
        assert.same({ Enabled = true }, profile.KeystoneHelper)
        assert.is_nil(profile.PartyBuffs)
        assert.is_nil(profile.HuntersMark)
        assert.is_nil(profile.VantusRune)
        -- The container keeps its admitted sub-blocks; AceDB refills a dropped one.
        assert.same({ EnemyCounter = { Enabled = true }, DungeonCasts = { Enabled = false } }, profile.Dungeons)
        assert.same({ "Dungeon Timers", "Hunters Mark", "Party Buffs" }, dropped)
    end)

    it("drops nothing but Forever-only blocks on a retail load", function()
        local PM = load(false)
        local profile = payload()
        local dropped = PM.FilterForClient(profile, DEFAULTS)
        assert.same(payload(), profile)
        assert.same({}, dropped)
    end)

    -- ForeverOnlyProbe stands for any Forever-only feature's block, at the top
    -- level and as a sub-block of the nested container.
    it("drops a Forever-only block on a retail load, names it when it was on, and keeps the rest", function()
        local PM = load(false)
        for _, row in ipairs({
            { name = "on",  enabled = true,  want = { "Forever Only Probe", "Forever Only Probe" } },
            { name = "off", enabled = false, want = {} },
        }) do
            local profile = payload()
            profile.ForeverOnlyProbe = { Enabled = row.enabled }
            profile.Dungeons.ForeverOnlyProbe = { Enabled = row.enabled }
            local dropped = PM.FilterForClient(profile, DEFAULTS)
            assert.same(row.want, dropped, row.name)
            assert.same(payload(), profile, row.name)
        end
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

describe("ProfileManager:ExportProfile on a baseline load", function()
    it("exports a filtered, tagged copy on a baseline load and leaves the live profile whole", function()
        local PM, KE = load(true)
        local live = payload()
        KE.db = { profiles = { Live = live } }
        local sent
        KE.EncodeForExport = function(_, envelope) sent = envelope; return "x" end
        assert.equals("!KE2!x", PM:ExportProfile("Live"))
        assert.equals(2, sent._v)
        assert.equals("forever", sent._c)
        assert.is_table(sent.d.DamageMeter)
        assert.is_nil(sent.d.PartyBuffs)
        assert.is_table(sent.d.Dungeons.EnemyCounter)
        assert.is_nil(sent.d.Dungeons.DungeonTimers)
        assert.same(payload(), live)
    end)
end)
