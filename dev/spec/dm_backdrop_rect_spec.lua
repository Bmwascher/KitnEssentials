-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_backdrop_rect_spec.lua                      ║
-- ║  The Damage Meter side of the Chat size sync.            ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Dock.lua headlessly (L.loadDMDock) and
-- tests three functions: DM.GetBackdropRectSize, which reports the backdrop
-- carrier rectangle Chat is sized to; DM.PushSizeToChat, which tells Chat the
-- rectangle changed; and DM.ReleaseChatSize, which hands Chat back its own size
-- when the module is disabled.
--
-- WHY THESE EARN A SPEC. None of it is a port -- there is no upstream feature
-- to diff against -- so a test is the only mechanical check there is. The
-- rectangle arithmetic branches on two settings and has five nil paths. The
-- push and the release are guard-ordering rules whose failures are all silent:
-- a memo written at the wrong moment suppresses a resize nobody sees fail, and
-- a memo left uncleared makes a re-enabled meter stop matching with no error.
--
-- NOT tested here, per the project's tiered policy: the Chat-side resolver
-- (a chain of guards one line from its own assertion), the GUI wiring, the
-- greying, and anything about what a frame actually measures on screen.
--
-- HONESTY BOUNDARY (see dev/README.md): the loader's PixelSnap is an identity
-- stub and the Chat module here is a three-field stand-in. A pass verifies
-- BRANCH ROUTING and CALL ORDERING over plain numbers, never real frame
-- geometry or the real Chat module. In-game /reload remains the gate for both.
local L = require("dev.spec._ke_loader")

local DM

-- One meter state. Every field is a plain number or boolean that LayoutDock
-- would have stashed; nothing here builds a frame, and nothing needs to.
local function meter(contentW, contentH, pad, behindBars, headerH, backdropOff)
    DM.enabled = true
    DM.db = {
        BackdropPadding       = pad,
        BackdropBehindBarsOnly = behindBars or false,
        BackdropEnabled       = not backdropOff,
    }
    DM._dockContentW = contentW
    DM._dockContentH = contentH
    DM._dockHeaderH  = headerH
end

before_each(function()
    DM = L.loadDMDock()
    assert(DM.GetBackdropRectSize, "loadDMDock did not expose GetBackdropRectSize")
end)

describe("GetBackdropRectSize reports the carrier", function()
    it("wraps the whole dock when the backdrop covers it", function()
        meter(400, 300, 4, false, 18)
        local w, h = DM:GetBackdropRectSize()
        assert.equals(408, w)
        assert.equals(308, h)
    end)

    it("drops one header band when the backdrop is behind bars only", function()
        meter(400, 300, 4, true, 18)
        local w, h = DM:GetBackdropRectSize()
        assert.equals(408, w)
        assert.equals(290, h)
    end)

    it("loses the padding on BOTH axes when the backdrop is off", function()
        -- _BackdropPad answers 0 for a disabled backdrop regardless of the
        -- configured padding, so the carrier collapses to the dock itself.
        meter(400, 300, 4, false, 18, true)
        local w, h = DM:GetBackdropRectSize()
        assert.equals(400, w)
        assert.equals(300, h)
    end)

    it("does NOT drop the header when the backdrop is off but behind-bars is on", function()
        -- UpdateBackdrop only honours the flag while the backdrop is enabled.
        -- A build that dropped the enabled half of the condition passes every
        -- other case here and fails this one.
        meter(400, 300, 4, true, 18, true)
        local w, h = DM:GetBackdropRectSize()
        assert.equals(400, w)
        assert.equals(300, h)
    end)

    it("returns the content size unchanged at zero padding", function()
        meter(240, 176, 0, false, 18)
        local w, h = DM:GetBackdropRectSize()
        assert.equals(240, w)
        assert.equals(176, h)
    end)
end)

describe("GetBackdropRectSize refusals", function()
    it("refuses while the module is disabled", function()
        meter(400, 300, 4, false, 18)
        DM.enabled = false
        assert.is_nil(DM:GetBackdropRectSize())
    end)

    it("refuses with no db", function()
        meter(400, 300, 4, false, 18)
        DM.db = nil
        assert.is_nil(DM:GetBackdropRectSize())
    end)

    it("refuses before any layout has stashed a width", function()
        meter(400, 300, 4, false, 18)
        DM._dockContentW = nil
        assert.is_nil(DM:GetBackdropRectSize())
    end)

    it("refuses before any layout has stashed a height", function()
        meter(400, 300, 4, false, 18)
        DM._dockContentH = nil
        assert.is_nil(DM:GetBackdropRectSize())
    end)

    it("refuses a zero content width", function()
        meter(0, 300, 4, false, 18)
        assert.is_nil(DM:GetBackdropRectSize())
    end)

    it("refuses rather than returning a negative height", function()
        meter(20, 20, 0, true, 40)
        assert.is_nil(DM:GetBackdropRectSize())
    end)

    it("refuses when behind-bars is on and the header stash is missing", function()
        -- NOT the padded height, and NOT the height minus zero. Treating a
        -- missing stash as zero reports a rectangle one header band taller than
        -- the renderer draws, because the renderer's own fallback recomputes the
        -- header instead of dropping it.
        meter(400, 300, 4, true, nil)
        assert.is_nil(DM:GetBackdropRectSize())
    end)

    it("still answers normally when the header stash is missing and behind-bars is off", function()
        -- The stash is only consulted on the behind-bars path. Pins that the
        -- case above did not over-tighten the guard.
        meter(400, 300, 4, false, nil)
        local w, h = DM:GetBackdropRectSize()
        assert.equals(408, w)
        assert.equals(308, h)
    end)
end)

describe("PushSizeToChat and ReleaseChatSize", function()
    local CHAT, calls

    before_each(function()
        calls = 0
        CHAT = _G.KitnEssentials:GetModule("Chat")
        CHAT.db = { Enabled = true, MatchDamageMeterSize = true }
        CHAT.panel = {}
        CHAT.UpdatePanel = function() calls = calls + 1 end
        meter(400, 300, 4, false, 18)
    end)

    it("tells Chat the first time", function()
        DM:PushSizeToChat()
        assert.equals(1, calls)
    end)

    it("says nothing when the rectangle has not moved", function()
        -- The splitter drag case: the dock re-lays out every frame while the
        -- user drags, and UpdatePanel walks every chat frame in the game.
        DM:PushSizeToChat()
        DM:PushSizeToChat()
        DM:PushSizeToChat()
        assert.equals(1, calls)
    end)

    it("tells Chat again once the rectangle changes", function()
        DM:PushSizeToChat()
        DM._dockContentH = 340
        DM:PushSizeToChat()
        assert.equals(2, calls)
    end)

    it("writes NO memo while the toggle is off", function()
        -- A memo written here would go stale and suppress the first real push
        -- after the user turns the sync on.
        CHAT.db.MatchDamageMeterSize = false
        DM:PushSizeToChat()
        assert.equals(0, calls)
        assert.is_nil(DM._chatPushW)
    end)

    it("refuses for a disabled Chat module", function()
        -- Chat's own teardown hides the panel but leaves it allocated, so the
        -- panel test below cannot cover this.
        CHAT.db.Enabled = false
        DM:PushSizeToChat()
        assert.equals(0, calls)
    end)

    it("refuses when Chat has no panel", function()
        CHAT.panel = nil
        DM:PushSizeToChat()
        assert.equals(0, calls)
    end)

    it("writes no memo when the meter has no rectangle", function()
        DM._dockContentW = nil
        DM:PushSizeToChat()
        assert.equals(0, calls)
        assert.is_nil(DM._chatPushW)
    end)

    it("clears the memo even when Chat is not eligible", function()
        DM:PushSizeToChat()
        CHAT.db.MatchDamageMeterSize = false
        DM:ReleaseChatSize()
        assert.is_nil(DM._chatPushW)
        assert.is_nil(DM._chatPushH)
    end)

    it("tells an eligible Chat once on release", function()
        DM:ReleaseChatSize()
        assert.equals(1, calls)
    end)

    it("lets an unchanged meter re-match after a disable and re-enable", function()
        -- Counting matters here. Without the memo clear the release still makes
        -- the SECOND call and the re-push is then suppressed, so a test that
        -- only checked for a final total of two would pass the broken build.
        -- The THIRD call is the whole case.
        DM:PushSizeToChat()
        assert.equals(1, calls)

        DM.enabled = false
        DM:ReleaseChatSize()
        assert.equals(2, calls)

        DM.enabled = true
        DM:PushSizeToChat()
        assert.equals(3, calls)
    end)
end)
