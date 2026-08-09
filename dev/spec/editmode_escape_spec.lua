-- Tier 1: refusal rule. Escape backs out one layer at a time, and the layer it
-- picks decides whether a session survives. Getting it wrong is silent: closing
-- a list you opened by mistake would throw away every unsaved drag instead.
local L = require("dev.spec._ke_loader")

describe("EditMode:HandleEscape", function()
    local KE, EditMode, closed, exited

    -- A nudge frame is a real frame in game. Everything this branch reads from
    -- it is one boolean, so the stub is that boolean and nothing else.
    local function nudgeWithList(shown)
        return { categoryList = { IsShown = function() return shown end } }
    end

    before_each(function()
        KE = L.loadGlobals()
        EditMode = L.loadEditMode(KE)

        closed, exited = 0, 0
        EditMode.CloseCategoryList = function() closed = closed + 1 end
        EditMode.Exit = function() exited = exited + 1 end
    end)

    it("closes an open list and leaves the tool running", function()
        EditMode.nudgeFrame = nudgeWithList(true)

        EditMode:HandleEscape()

        assert.equals(1, closed)
        assert.equals(0, exited)
    end)

    -- The decoy that gives the case above its meaning: without this, a handler
    -- that always closed the list would pass and Escape would never exit.
    it("exits when the list is closed", function()
        EditMode.nudgeFrame = nudgeWithList(false)

        EditMode:HandleEscape()

        assert.equals(0, closed)
        assert.equals(1, exited)
    end)

    it("exits when the tool has never been built", function()
        EditMode.nudgeFrame = nil

        EditMode:HandleEscape()

        assert.equals(1, exited)
    end)

    it("exits when the tool exists but carries no list", function()
        EditMode.nudgeFrame = {}

        EditMode:HandleEscape()

        assert.equals(1, exited)
    end)

    -- One Escape per layer. A handler that closed the list and exited in the
    -- same press would satisfy every case above except this one.
    it("never closes and exits on the same press", function()
        EditMode.nudgeFrame = nudgeWithList(true)

        EditMode:HandleEscape()

        assert.equals(0, exited)
    end)
end)
