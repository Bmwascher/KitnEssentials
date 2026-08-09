-- Tier 2: the rebuild refusal in GUI/GUIMain/GUI-Core.lua RefreshContent.
--
-- This is a guard rule, not layout. Rebuilding orphans a page of frames via
-- SetParent(nil) and WoW never collects a frame, so a caller that fires while
-- the page is off screen leaks permanently — the guard's own comment records
-- reaching hundreds of thousands in one session. Collapsing the window leaves
-- the frame Shown, so the original test passed and the refusal was bypassed;
-- edit-mode writes a position on every drop, which made that the busiest
-- caller in the addon.
--
-- Only the refusal and the replay flag are asserted. Everything past the guard
-- is real frame work and is verified in game.
local helpers = require("dev.spec._helpers")

describe("GUI-Core RefreshContent guard", function()
    local GUIFrame, rebuilt

    -- The file only reads KE.Theme at load and defines onto KE.GUIFrame, so it
    -- loads against a seed with no Blizzard fakes beyond a frame that answers
    -- IsShown.
    before_each(function()
        local KE = { Theme = { headerHeight = 32, borderSize = 1 } }
        helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
        GUIFrame = KE.GUIFrame

        rebuilt = 0
        -- Fires immediately after the guard passes and nowhere else, so it is
        -- the honest witness for "did a rebuild actually start".
        GUIFrame.contentRebuildCallbacks = { function() rebuilt = rebuilt + 1 end }
        GUIFrame.contentArea = {}
        GUIFrame.mainFrame = { IsShown = function() return true end }
    end)

    it("refuses to rebuild while the window is collapsed", function()
        GUIFrame.minimized = true

        GUIFrame:RefreshContent()

        assert.equals(0, rebuilt)
        assert.is_true(GUIFrame._contentDirtyWhileHidden)
    end)

    it("refuses to rebuild while the window is hidden", function()
        GUIFrame.minimized = false
        GUIFrame.mainFrame = { IsShown = function() return false end }

        GUIFrame:RefreshContent()

        assert.equals(0, rebuilt)
        assert.is_true(GUIFrame._contentDirtyWhileHidden)
    end)

    -- The decoy that makes the first case meaningful: with neither condition
    -- set the guard must NOT fire, or both tests above would pass against a
    -- function that refuses everything.
    it("does not refuse when the window is open and expanded", function()
        GUIFrame.minimized = false

        -- Everything past the guard is real frame work, so it throws against
        -- these stubs. Reaching the throw IS the assertion: the guard let it
        -- through and the rebuild callbacks fired first.
        pcall(GUIFrame.RefreshContent, GUIFrame)

        assert.equals(1, rebuilt)
        assert.is_nil(GUIFrame._contentDirtyWhileHidden)
    end)

    -- Collapsed AND closed at once is reachable — minimise, then click the X.
    -- Covered explicitly because a guard that tested the two conditions against
    -- each other rather than either-or would refuse each alone and rebuild
    -- when both hold, which is the worst of the three states.
    it("refuses to rebuild while collapsed and hidden together", function()
        GUIFrame.minimized = true
        GUIFrame.mainFrame = { IsShown = function() return false end }

        GUIFrame:RefreshContent()

        assert.equals(0, rebuilt)
        assert.is_true(GUIFrame._contentDirtyWhileHidden)
    end)

    -- The flag must survive every refusal, not just be true once the run ends.
    -- Asserted after each call because a guard that toggled the flag would
    -- read as correct on any odd number of them.
    it("keeps the dirty flag set on every repeated refusal", function()
        GUIFrame.minimized = true

        for _ = 1, 4 do
            GUIFrame:RefreshContent()
            assert.equals(0, rebuilt)
            assert.is_true(GUIFrame._contentDirtyWhileHidden)
        end
    end)

    -- The recovery the whole mechanism exists for, and the only case that
    -- catches a guard which refuses because a refusal already happened: such a
    -- guard passes every case above and then never lets the page rebuild
    -- again, so expanding shows the state from before the last drag forever.
    it("rebuilds once the window comes back, and clears the flag", function()
        GUIFrame.minimized = true
        GUIFrame:RefreshContent()
        assert.is_true(GUIFrame._contentDirtyWhileHidden)

        GUIFrame.minimized = false
        pcall(GUIFrame.RefreshContent, GUIFrame)

        assert.equals(1, rebuilt)
        assert.is_nil(GUIFrame._contentDirtyWhileHidden)
    end)
end)
