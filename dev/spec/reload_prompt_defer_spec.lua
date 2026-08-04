-- Tier 2: Core/Widgets.lua -- the deferred skinning reload prompt.
--
-- Skinning toggles call KE:FlagReloadNeeded instead of prompting; the GUI
-- frame's OnHide calls KE:FlushPendingReloadPrompt, so a user who ticks eight
-- windows gets one prompt on the way out instead of eight interruptions.
--
-- The refusal rule pinned here is the COMBAT gate. Entering combat hides this
-- GUI (GUI/GUIMain/GUI-MainFrame.lua:682-698), so without the gate a pending
-- skin change puts a "Reload Now" button on screen at the pull, one misclick
-- from reloading mid-fight. The flag must SURVIVE that close, because the same
-- handler reopens the GUI when combat ends and the next ordinary close is what
-- should raise the prompt.
--
-- There are TWO gates and the reopenAfterCombat one is load-bearing. The first
-- attempt gated on InCombatLockdown alone and the prompt still appeared in game
-- (2026-08-04), so the examples below cover each gate on its own -- passing one
-- must never stand in for the other.
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

    -- The refusal rule, gate one: the combat AUTO-CLOSE. This is the gate that
    -- actually fires in game. GUI-MainFrame's combat handler sets
    -- reopenAfterCombat and then hides the frame, so OnHide runs with the flag
    -- already set, whatever the combat API happens to report at that instant.
    it("refuses to prompt when the GUI is closing for combat", function()
        KE.GUIFrame = { reopenAfterCombat = true }
        KE:FlagReloadNeeded()
        KE:FlushPendingReloadPrompt()
        assert.equals(0, prompts)
    end)

    it("KEEPS the flag through the combat auto-close, so the reopen-and-close prompts", function()
        KE.GUIFrame = { reopenAfterCombat = true }
        KE:FlagReloadNeeded()
        KE:FlushPendingReloadPrompt()
        assert.equals(0, prompts)

        -- Combat ends: the handler clears the flag and reopens. The user then
        -- closes normally.
        KE.GUIFrame.reopenAfterCombat = nil
        KE:FlushPendingReloadPrompt()
        assert.equals(1, prompts)
    end)

    it("a normal close with a GUIFrame present still prompts", function()
        -- Positive control for the gate above: the flag, not the presence of a
        -- GUIFrame, is what suppresses.
        KE.GUIFrame = {}
        KE:FlagReloadNeeded()
        KE:FlushPendingReloadPrompt()
        assert.equals(1, prompts)
    end)

    -- Gate two: a user who opened this GUI during combat and closes it himself
    -- never sets reopenAfterCombat, so the API check is the only thing left.
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
