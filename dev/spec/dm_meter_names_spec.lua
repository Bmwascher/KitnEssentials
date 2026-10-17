-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_meter_names_spec.lua                        ║
-- ║  Damage Meter two-line detail rows: pure rules.          ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/Skinning/DamageMeter/Detail.lua through its EOF seam (as
-- dm_breakdown_spec.lua does) and tests the rules the two-line detail rows
-- depend on: which recap rows show a gray name, and the row geometry.
-- Anchors, fonts and mouse events are smoke.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue is a stub and secrecy is
-- whatever this file declares. KE:PixelSnap is stubbed as round-to-nearest on a
-- grid of PX units and KE:GetPixelSize returns PX: 1 (a pixel-perfect UI scale)
-- unless a case sets another pixel size.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local SECRET = {}   -- [value] = true  marks a value "secret"
local PX = 1        -- the stubbed pixel size, in UI units

local function loadDetail()
    for k in pairs(SECRET) do SECRET[k] = nil end
    PX = 1
    -- Detail.lua captures issecretvalue / C_Spell into file-locals at load.
    mock.install({ issecretvalue = function(v) return SECRET[v] == true end })
    _G.C_Spell = { GetSpellName = function() return nil end,
                   GetSpellTexture = function() return nil end }
    local modules = helpers.installAddonShim()
    local KE = {
        PixelSnap = function(_, v) return math.floor(v / PX + 0.5) * PX end,
        GetPixelSize = function() return PX end,
    }
    helpers.loadModule("Modules/Skinning/DamageMeter/Detail.lua", KE)
    local DM = modules["DamageMeter"]
    assert(DM.RecapSourceSuffix, "Detail.lua seam did not expose RecapSourceSuffix")
    return DM
end

describe("RecapSourceSuffix", function()
    local DM
    before_each(function() DM = loadDetail() end)

    it("adds the gray name on a damage row in both layouts", function()
        local want = "  |cff999999(Darkcaller)|r"
        assert.equals(want, DM.RecapSourceSuffix("Darkcaller", false, nil))
        assert.equals(want, DM.RecapSourceSuffix("Darkcaller", false, true))
    end)

    it("adds the healer on a heal row only on the two-line panel row", function()
        assert.equals("  |cff999999(Lightbringer)|r", DM.RecapSourceSuffix("Lightbringer", true, true))
        assert.equals("", DM.RecapSourceSuffix("Lightbringer", true, nil))
    end)

    it("shows no name when it is secret, missing or empty", function()
        SECRET["Hidden"] = true
        for _, case in ipairs({ { name = "Hidden" }, { name = nil }, { name = "" } }) do
            for _, isHeal in ipairs({ false, true }) do
                for _, twoLine in ipairs({ false, true }) do
                    assert.equals("", DM.RecapSourceSuffix(case.name, isHeal, twoLine))
                end
            end
        end
    end)
end)

describe("DetailRowMetrics", function()
    local DM
    before_each(function() DM = loadDetail() end)

    it("derives the two-line row from the bar height, spacing and font size", function()
        -- Bar term 23 + 9 = 32 beats the minimum 1.25 x (14 + 11) = 31.
        local m = DM.DetailRowMetrics(23, 1, 14)
        assert.equals(11, m.sub)
        assert.equals(32, m.rowH)
        assert.equals(33, m.stride)
        assert.equals(10, m.line1Y)
        assert.equals(24, m.line2Y)
    end)

    it("floors the line-2 font size at 8 and sizes the row from the floored size", function()
        -- FontSize 9 would give a line-2 size of 6 (row 28); the floor gives 8 (row 29).
        local m = DM.DetailRowMetrics(23, 1, 9)
        assert.equals(8, m.sub)
        assert.equals(29, m.rowH)
    end)

    it("raises a short bar with large text to the two-line minimum", function()
        -- Bar term 8 + 17 = 25 is below the minimum 1.25 x (24 + 21) = 56.
        local m = DM.DetailRowMetrics(8, 1, 24)
        assert.equals(21, m.sub)
        assert.equals(56, m.rowH)
        assert.equals(57, m.stride)
        assert.equals(18, m.line1Y)
        assert.equals(41, m.line2Y)
    end)

    it("keeps the lines apart on a pixel grid that is not one unit", function()
        -- At pixel size 1.6 the snapped 0.74 center is 20.8, only 11.2 below line 1's
        -- 9.6; sizes 13 and 10 need 11.5, so line 2 moves to 9.6 + 12.8 = 22.4.
        PX = 1.6
        local m = DM.DetailRowMetrics(8, 1.6, 13)
        assert.equals(10, m.sub)
        assert.near(28.8, m.rowH, 1e-9)
        assert.near(9.6, m.line1Y, 1e-9)
        assert.near(22.4, m.line2Y, 1e-9)
    end)

    it("grows the row so line 2 ends inside it on a pixel grid that is not one unit", function()
        -- At pixel size 1.3 the minimum row is 19.5, but line 2 sits at 6.5 + 9.1 = 15.6
        -- and needs half its size (rounded up to 5.2) below it, so the row becomes 20.8.
        PX = 1.3
        local m = DM.DetailRowMetrics(7.8, 1.3, 8)
        assert.near(15.6, m.line2Y, 1e-9)
        assert.near(20.8, m.rowH, 1e-9)
    end)
end)
