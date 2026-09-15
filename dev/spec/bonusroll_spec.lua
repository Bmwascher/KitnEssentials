-- luacheck: std lua51+busted
-- Modules/QoL/BonusRoll.lua -- the rules a later edit breaks silently: which
-- content bucket a prompt falls in, whether it is passed for the player,
-- whether a dialog button may still press Blizzard's button, and whether the
-- module may close the prompt singleton. The close case uses a two-field
-- stand-in for the singleton (`_onAccept` and Hide) because the guard is a
-- comparison against that field and nothing else.

local L = require("dev.spec._ke_loader")

describe("BonusRoll", function()
    local BR, KE

    before_each(function()
        BR, KE = L.loadBonusRoll()
    end)

    it("files a prompt by instance type and difficulty", function()
        local cases = {
            { "raid", 17, false, "RaidLFR" },
            { "raid", 220, false, "RaidNormal" },
            { "raid", 15, false, "RaidHeroic" },
            { "raid", 233, false, "RaidMythic" },
            { "raid", 151, false, "RaidTimewalking" },
            { "party", 2, false, "DungeonNormalHeroic" },
            { "party", 8, false, "DungeonMythic" },
            { "party", 24, false, "DungeonTimewalking" },
            { "scenario", 0, true, "Delves" },
            { "scenario", 0, false, "Scenarios" },
            { "none", 0, false, "OpenWorld" },
            { "pvp", 0, false, nil },
            { "raid", 999, false, nil },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[4], BR.BucketFor(c[1], c[2], c[3]), c[1] .. "/" .. tostring(c[2]))
        end
    end)

    it("passes only when the feature is on and the bucket is ticked", function()
        local ticked = { OpenWorld = true, RaidLFR = false }
        assert.is_false(BR.ShouldAutoPass(false, ticked, "OpenWorld"))
        assert.is_false(BR.ShouldAutoPass(true, ticked, nil))
        assert.is_false(BR.ShouldAutoPass(true, ticked, "RaidLFR"))
        assert.is_false(BR.ShouldAutoPass(true, ticked, "RaidNormal"))
        assert.is_false(BR.ShouldAutoPass(true, nil, "OpenWorld"))
        assert.is_true(BR.ShouldAutoPass(true, ticked, "OpenWorld"))
    end)

    it("lets a dialog button press only a live prompt with the feature on", function()
        -- kind, featureOn, state, promptShown, promptVisible, buttonShown, buttonEnabled
        assert.is_true(BR.PromptLive("roll", true, "prompt", true, true, true, true))
        assert.is_false(BR.PromptLive("roll", false, "prompt", true, true, true, true))
        assert.is_false(BR.PromptLive("roll", true, "rolling", true, true, true, true))
        assert.is_false(BR.PromptLive("roll", true, "prompt", false, true, true, true))
        assert.is_false(BR.PromptLive("roll", true, "prompt", true, false, true, true))
        assert.is_false(BR.PromptLive("roll", true, "prompt", true, true, false, true))
        assert.is_false(BR.PromptLive("roll", true, "prompt", true, true, true, false))
        -- Pass never needs the button enabled; only Roll is disabled while rolling.
        assert.is_true(BR.PromptLive("pass", true, "prompt", true, true, true, false))
    end)

    it("closes only the dialog it opened", function()
        local mine = function() end
        local function dialog(accept)
            return { _onAccept = accept, _onCancel = function() end, hidden = false,
                     Hide = function(self) self.hidden = true end }
        end

        local other = dialog(function() end)
        KE.activePrompt = other
        BR:ClosePrompt()
        assert.is_false(other.hidden)

        BR.pending, BR.pendingAccept = "roll", mine
        BR:ClosePrompt()
        assert.is_false(other.hidden)
        assert.is_nil(BR.pending)

        local ours = dialog(mine)
        KE.activePrompt = ours
        BR.pending, BR.pendingAccept = "roll", mine
        BR:ClosePrompt()
        assert.is_true(ours.hidden)
        assert.is_nil(ours._onAccept)
        assert.is_nil(ours._onCancel)
        assert.is_nil(KE.activePrompt)
    end)
end)
