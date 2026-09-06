-- Tier 2: the mode rule is a guard whose failures are silent. A wrong answer
-- does not error, it relocates the frame and redraws the wrong layout. The
-- held-value behaviour is as load-bearing as the rule itself.
local L = require("dev.spec._ke_loader")

describe("HealerMana mode resolution", function()
    it("reports RAID while in a raid group", function()
        local HM = L.loadHealerMana({ IsInRaid = function() return true end })
        HM:RefreshMode()
        assert.are.equal("RAID", HM:GetMode())
    end)

    it("reports DUNGEON while in a party", function()
        local HM = L.loadHealerMana({ IsInRaid = function() return false end })
        HM:RefreshMode()
        assert.are.equal("DUNGEON", HM:GetMode())
    end)

    it("stays DUNGEON in a raid group when Enable in Raid is off", function()
        local HM = L.loadHealerMana({ IsInRaid = function() return true end })
        HM.db.EnableInRaid = false
        HM:RefreshMode()
        assert.are.equal("DUNGEON", HM:GetMode())
    end)

    it("reports a change only when the mode actually moved", function()
        local inRaid = false
        local HM = L.loadHealerMana({ IsInRaid = function() return inRaid end })
        HM:RefreshMode()
        assert.is_false(HM:RefreshMode())
        inRaid = true
        assert.is_true(HM:RefreshMode())
        assert.is_false(HM:RefreshMode())
    end)

    it("does not consult the game once the mode is held", function()
        -- Reading must be inert. A reader that queries can disagree with the
        -- reader beside it, which is what makes the position table swap.
        local calls = 0
        local HM = L.loadHealerMana({
            IsInRaid = function() calls = calls + 1; return true end,
        })
        HM:RefreshMode()
        local baseline = calls
        HM:GetMode()
        HM:GetMode()
        assert.are.equal(baseline, calls)
    end)
end)

-- Tier 2: a guard whose failure is silent. Lifted into a predicate so the
-- case needs no raid roster fake; the loop that consults it is covered by
-- the diff.
describe("HealerMana:ExcludesSelf", function()
    it("is true only when the raid toggle is on and the player's spec heals", function()
        for _, case in ipairs({
            { toggle = true,  healer = true,  expected = true },
            { toggle = true,  healer = false, expected = false },
            { toggle = false, healer = true,  expected = false },
            { toggle = false, healer = false, expected = false },
        }) do
            local HM, KE = L.loadHealerMana()
            KE.IsPlayerHealerSpec = function() return case.healer end
            HM.db.ExcludeSelfHealer = case.toggle
            assert.are.equal(case.expected, HM:ExcludesSelf(),
                "toggle=" .. tostring(case.toggle) .. " healer=" .. tostring(case.healer))
        end
    end)
end)

describe("HealerMana:PreviewContext", function()
    it("answers with the page's context only while the page is open", function()
        for _, case in ipairs({
            { guiOpen = true,  context = "RAID",    expected = "RAID" },
            { guiOpen = true,  context = "DUNGEON", expected = "DUNGEON" },
            { guiOpen = true,  context = nil,       expected = nil },
            { guiOpen = false, context = "RAID",    expected = nil },
            { guiOpen = false, context = nil,       expected = nil },
        }) do
            local HM, KE = L.loadHealerMana()
            KE.PreviewManager = { guiOpen = case.guiOpen }
            HM.previewContext = case.context
            assert.are.equal(case.expected, HM:PreviewContext(),
                "guiOpen=" .. tostring(case.guiOpen) .. " context=" .. tostring(case.context))
        end
    end)
end)
