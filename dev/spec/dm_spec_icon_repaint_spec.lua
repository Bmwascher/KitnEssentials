-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_spec_icon_repaint_spec.lua                  ║
-- ║  A spec icon learned over comms repaints quiet windows.  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- WHY THIS EARNS A SPEC: the rule decides when a changed spec icon forces every
-- window to repaint, and a wrong answer is silent. A quiet window keeps the
-- class icon for the rest of the pull, or every repeated report repaints every
-- window. The fakes are plain lookups over a fixed party, not a Blizzard
-- subsystem.
local L = require("dev.spec._ke_loader")

-- Core.lua captures both at file scope and the loader manages neither, so they
-- are on _G before the load and restored after.
local STUBBED = { "Ambiguate", "GetSpecializationInfoForSpecID" }

local DM, saved, names, guids

-- The sum a window on meter type 0 records at its paint.
local function windowSum()
    return (DM._typeSeq[0] or 0) + DM._allSeq
end

before_each(function()
    saved = {}
    for _, key in ipairs(STUBBED) do saved[key] = _G[key] end
    _G.Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
    _G.GetSpecializationInfoForSpecID = function(specID)
        return specID, "Spec", nil, specID * 10
    end
    -- Read at call time, so a case can rename a member after the load.
    names = { player = "Me", party1 = "Ann", party2 = "Bob" }
    guids = { player = "Player-1", party1 = "Player-A", party2 = "Player-B" }
    DM = L.loadDMCore({
        UnitName = function(unit) return names[unit] end,
        UnitGUID = function(unit) return guids[unit] end,
        IsInGroup = function() return true end,
        GetNumGroupMembers = function() return 3 end,
    })
end)

after_each(function()
    for _, key in ipairs(STUBBED) do _G[key] = saved[key] end
end)

describe("OnLibSpecGroupUpdate", function()
    it("moves the untyped counter only when a member's stored icon changes", function()
        -- stored: Ann's icon before the report. Spec 62 reports icon 620.
        local cases = {
            { name = "first report", stored = nil, spec = 62, who = "Ann", moves = true },
            { name = "a different icon", stored = 630, spec = 62, who = "Ann", moves = true },
            { name = "a repeat of the stored icon", stored = 620, spec = 62, who = "Ann", moves = false },
            { name = "an unknown spec", stored = nil, spec = 0, who = "Ann", moves = false },
            { name = "a name not in the group", stored = nil, spec = 62, who = "Zed", moves = false },
        }
        for _, c in ipairs(cases) do
            DM.specIconByGUID["Player-A"] = c.stored
            local before = windowSum()
            DM:OnLibSpecGroupUpdate(c.spec, "DAMAGER", nil, c.who)
            local after = windowSum()
            assert.equals(c.moves and 1 or 0, after - before, c.name)
            assert.equals(not c.moves, DM.PaintSkip(0, before, 0, after, false), c.name)
        end
    end)

    it("bumps once for a shared name that purged a stored icon, then not again", function()
        names.party2 = "Ann"
        -- Either colliding member may hold the icon.
        for _, holder in ipairs({ "Player-A", "Player-B" }) do
            DM.specIconByGUID[holder] = 620
            local before = DM._allSeq
            DM:OnLibSpecGroupUpdate(62, "DAMAGER", nil, "Ann")
            assert.equals(1, DM._allSeq - before, holder)
            assert.is_nil(DM.specIconByGUID[holder], holder)
            DM:OnLibSpecGroupUpdate(62, "DAMAGER", nil, "Ann")
            assert.equals(1, DM._allSeq - before, holder .. " repeated")
        end
    end)
end)
