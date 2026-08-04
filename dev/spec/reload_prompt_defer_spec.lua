-- Tier 2: Core/Widgets.lua -- the deferred skinning reload prompt.
--
-- Skinning toggles call KE:FlagReloadNeeded instead of prompting; the GUI
-- frame's OnHide calls KE:FlushPendingReloadPrompt, so a user who ticks eight
-- windows gets one prompt on the way out instead of eight interruptions.
--
-- The refusal rule pinned here is the COMBAT gate. Entering combat hides this
-- GUI (GUI/GUIMain/GUI-MainFrame.lua:243-251), so without the gate a pending
-- skin change puts a "Reload Now" button on screen at the pull, one misclick
-- from reloading mid-fight. The flag must SURVIVE that close, because the same
-- handler reopens the GUI when combat ends and the next ordinary close is what
-- should raise the prompt.
--
-- Loaded against a hand-built KE rather than the real one: this file only needs
-- the two functions and the CreateReloadPrompt they call, and Core/Widgets.lua
-- builds nothing at load time.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("Core/Widgets.lua deferred reload prompt", function()
    local KE, prompts, inCombat

    before_each(function()
        inCombat = false
        mock.install({ InCombatLockdown = function() return inCombat end })
        prompts = 0
        KE = helpers.loadModule("Core/Widgets.lua", {})
        -- Replaced AFTER the load, not seeded before it: Core/Widgets.lua
        -- defines CreateReloadPrompt itself and would overwrite a seed. Counts
        -- prompts without building one -- the real path goes through
        -- CreatePrompt, StaticPopupDialogs and a pile of frames, and what this
        -- file is about is WHETHER it is called.
        KE.CreateReloadPrompt = function() prompts = prompts + 1 end
    end)

    it("does not prompt while nothing is pending", function()
        KE:FlushPendingReloadPrompt()
        assert.equals(0, prompts)
    end)

    it("prompts once on close after any number of flags", function()
        KE:FlagReloadNeeded()
        KE:FlagReloadNeeded()
        KE:FlagReloadNeeded()
        KE:FlushPendingReloadPrompt()
        assert.equals(1, prompts)
    end)

    it("clears the flag, so a second close is silent", function()
        KE:FlagReloadNeeded()
        KE:FlushPendingReloadPrompt()
        KE:FlushPendingReloadPrompt()
        assert.equals(1, prompts)
    end)

    -- The refusal rule.
    it("refuses to prompt in combat", function()
        KE:FlagReloadNeeded()
        inCombat = true
        KE:FlushPendingReloadPrompt()
        assert.equals(0, prompts)
    end)

    it("KEEPS the flag through a combat close, so the next close still prompts", function()
        -- The half that matters. Refusing but clearing would swallow the prompt
        -- entirely: the user would never be told a reload was owed.
        KE:FlagReloadNeeded()
        inCombat = true
        KE:FlushPendingReloadPrompt()
        assert.equals(0, prompts)

        inCombat = false
        KE:FlushPendingReloadPrompt()
        assert.equals(1, prompts)
    end)
end)
