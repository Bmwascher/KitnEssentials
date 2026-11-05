-- Tier 2: Swing Timer's registration in EllesmereUI's unlock mode. The cases
-- capture the module's real closures off a recording KE.EUIUnlock: isHidden for
-- a module that is off, and the setters unlock mode calls with a matched size,
-- which must write the profile like the page's sliders and stop when nothing
-- changed, or every resize re-applies the settings.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local function load()
    mock.install({})
    local modules = helpers.installAddonShim()
    local KE = helpers.loadModule("Modules/Combat/SwingTimer/SwingTimerRules.lua", {})
    helpers.loadModule("Modules/Combat/SwingTimer/SwingTimer.lua", KE)
    local rec = { applied = 0 }
    KE.EUIUnlock = { Register = function(_, config, opts) rec.config, rec.opts = config, opts end }
    KE.PixelSnap = function(_, value) return value end
    local ST = modules["SwingTimer"]
    ST.db = { Enabled = true, Width = 240, Height = 16, Spacing = 2 }
    ST.frame = {}
    ST.rowCount = 2
    ST.ApplySettings = function() rec.applied = rec.applied + 1 end
    ST:RegWithUnlock()
    return ST, rec, KE
end

describe("swing timer in unlock mode", function()
    after_each(function()
        mock.reset()
    end)

    it("hides a module that is off with its holder built, and shows one that is on", function()
        local ST, rec = load()
        ST.db.Enabled = false
        assert.is_true(rec.opts.isHidden())
        ST.db.Enabled = true
        assert.is_false(rec.opts.isHidden())
    end)

    it("writes a matched size once, the height shared over the rows", function()
        local ST, rec = load()
        rec.opts.setWidth(300)
        rec.opts.setWidth(300)
        rec.opts.setHeight(50)
        assert.equals(300, ST.db.Width)
        assert.equals(24, ST.db.Height)
        assert.equals(2, rec.applied)
    end)

    it("records a pulled axis only when the pull answers true, so a refused one is tried again", function()
        local ST, _, KE = load()
        local calls, answer = {}, { height = true, width = false }
        KE.EUIUnlock.PullMatch = function(_, _, axis)
            calls[#calls + 1] = axis
            return answer[axis]
        end
        local function stubFrame()
            return { ClearAllPoints = function() end, SetPoint = function() end, SetSize = function() end }
        end
        ST.bars = { MH = { frame = stubFrame(), known = true }, OH = { frame = stubFrame() }, R = { frame = stubFrame() } }
        ST.order = { "MH", "OH", "R" }
        ST.frame = stubFrame()
        ST.ApplyBarShown = function() end
        ST.UpdateHolder = function() end
        ST.LayoutTarget = function(_, slot) return slot - 1 end

        ST:LayoutBars()
        ST:LayoutBars()
        answer.width = true
        ST:LayoutBars()
        ST:LayoutBars()
        assert.same({ "height", "width", "width", "width" }, calls)
    end)
end)
