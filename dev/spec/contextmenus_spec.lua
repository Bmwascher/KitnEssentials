-- Modules/Skinning/ContextMenus.lua — the pre-layout guard in SkinFrame.
--
-- Why this file exists: Blizzard's menu system hands us a SUBMENU frame before
-- it has laid the frame out, and the frame reports 1x1 at that moment. Those
-- numbers are perfectly readable, so the module's secret-value test cannot
-- catch them, and every branch downstream trusts them. Acting on a 1x1
-- measurement is unrecoverable in one pass: the Blizzard art is stripped, our
-- replacement backdrop is built 1x1 and is therefore invisible, and the menu
-- then lays out to full size with its text drawn over nothing.
--
-- Diagnosed in game from a DEBUG_CM log that showed the root menu at
-- 164x342 and the submenu at 1x1 inside the same menu-open.

local L = require("dev.spec._ke_loader")

describe("ContextMenus SkinFrame — pre-layout guard", function()
    local SkinFrame, calls

    -- A stand-in for a Blizzard menu frame. Only the surface SkinFrame touches.
    local function menuFrame(w, h)
        return {
            GetWidth = function() return w end,
            GetHeight = function() return h end,
            GetFrameLevel = function() return 5 end,
        }
    end

    before_each(function()
        local _, _, seams, recorder = L.loadContextMenus()
        SkinFrame, calls = seams.SkinFrame, recorder
    end)

    it("exposes SkinFrame through the loader seam", function()
        -- Guard against a silent seam break: every assertion below would pass
        -- vacuously against a nil SkinFrame if it were only ever called
        -- inside a pcall, and a broken seam must not read as a passing suite.
        assert.is_function(SkinFrame)
    end)

    -- POSITIVE CONTROL. Without this, a SkinFrame that refused to skin
    -- ANYTHING would satisfy every negative assertion in this file.
    it("skins a laid-out menu and sizes the backdrop to the frame", function()
        SkinFrame(menuFrame(164, 342))
        assert.equals(1, #calls.stripped)
        assert.equals(1, #calls.backdrops)
        assert.equals(162, calls.backdrops[1].w)   -- w - 2
        assert.equals(340, calls.backdrops[1].h)   -- h - 2
        assert.is_true(calls.backdrops[1].shown)
    end)

    it("does NOT strip a frame that is still 1x1", function()
        SkinFrame(menuFrame(1, 1))
        assert.equals(0, #calls.stripped)
        assert.equals(0, #calls.backdrops)
    end)

    -- The two axes are checked separately, so a guard testing only width would
    -- pass the 1x1 case above while still destroying a tall, unlaid-out frame.
    it("guards on height alone", function()
        SkinFrame(menuFrame(200, 4))
        assert.equals(0, #calls.stripped)
    end)

    it("guards on width alone", function()
        SkinFrame(menuFrame(4, 200))
        assert.equals(0, #calls.stripped)
    end)

    -- Boundary in BOTH directions. One-sided boundary tests do not distinguish
    -- `< 16` from `<= 16`, and getting that wrong would refuse to skin a real
    -- (if unusually small) menu forever.
    it("skins at exactly the threshold and refuses one below it", function()
        SkinFrame(menuFrame(16, 16))
        assert.equals(1, #calls.stripped)
        SkinFrame(menuFrame(15, 15))
        assert.equals(1, #calls.stripped)   -- unchanged: the second was refused
    end)

    -- The guard must sit AFTER the secret-value test, not replace it: a secret
    -- dimension still has to reach the pooled-frame rescue, which is a
    -- different code path with different consequences.
    it("leaves a secret dimension to the rescue path, not the guard", function()
        SkinFrame(menuFrame("SECRET", "SECRET"))
        assert.equals(0, #calls.stripped)
        assert.equals(0, #calls.backdrops)   -- never stripped, so nothing to rebuild
    end)
end)
