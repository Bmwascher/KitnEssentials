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

    -- The keyboard-propagation flag lives on the frame, not on the key event,
    -- so once Escape can be consumed WITHOUT tearing the handler down, only the
    -- handler itself can re-open it. HandleEscape cannot see any of this: the
    -- defect that shipped was entirely in the closure around it, and left every
    -- later keypress swallowed, movement included.
    describe("keyboard propagation", function()
        local escapeFrame, propagate

        local function press(key)
            escapeFrame:GetScript("OnKeyDown")(escapeFrame, key)
        end

        before_each(function()
            EditMode:SetupEscapeHandler()
            escapeFrame = EditMode.escapeFrame
            propagate = nil
            escapeFrame.SetPropagateKeyboardInput = function(_, value)
                propagate = value
            end
        end)

        it("consumes the Escape it acts on", function()
            EditMode.nudgeFrame = nudgeWithList(true)

            press("ESCAPE")

            assert.is_false(propagate)
        end)

        it("lets the next key through after a consumed Escape", function()
            EditMode.nudgeFrame = nudgeWithList(true)

            press("ESCAPE")
            press("W")

            assert.is_true(propagate)
        end)

        it("never consumes a key it does not act on", function()
            EditMode.nudgeFrame = nudgeWithList(true)

            press("W")

            assert.is_true(propagate)
            assert.equals(0, closed)
            assert.equals(0, exited)
        end)
    end)
end)
