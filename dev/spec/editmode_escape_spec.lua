-- Tier 1: refusal rule. Escape backs out one layer at a time, and the layer it
-- picks decides whether a session survives. Getting it wrong is silent: closing
-- a list you opened by mistake would throw away every unsaved drag instead.
local L = require("dev.spec._ke_loader")

describe("EditMode:HandleEscape", function()
    local KE, EditMode, closed, exited, flyoutClosed, inCombat, ctrlDown

    -- A nudge frame is a real frame in game. Everything this branch reads from
    -- it is one boolean, so the stub is that boolean and nothing else.
    local function nudgeWithList(shown)
        return { categoryList = { IsShown = function() return shown end } }
    end

    -- The flyout layer. Two booleans rather than one, because the case that
    -- matters is a closed list with an open flyout: a handler that read only
    -- the first layer would exit the session instead of closing the flyout.
    local function nudgeWith(listShown, flyoutShown)
        return {
            categoryList = { IsShown = function() return listShown end },
            guidesFlyout = { IsShown = function() return flyoutShown end },
        }
    end

    before_each(function()
        inCombat = false
        -- Overridden at load, not after it: the module localizes
        -- InCombatLockdown at file scope, so a later swap never reaches it.
        KE = L.loadGlobals({ InCombatLockdown = function() return inCombat end })
        -- Same trap as InCombatLockdown, and the same shape of answer: the
        -- module localizes this at file scope, so the stub has to exist before
        -- the load and has to read a flag rather than be swapped per case. It
        -- cannot go through the loader either -- it is not a managed mock key,
        -- so an override handed over there is discarded.
        ctrlDown = false
        _G.IsControlKeyDown = function() return ctrlDown end
        EditMode = L.loadEditMode(KE)

        closed, exited, flyoutClosed = 0, 0, 0
        EditMode.CloseCategoryList = function() closed = closed + 1 end
        EditMode.CloseGuidesFlyout = function() flyoutClosed = flyoutClosed + 1 end
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

    it("closes an open flyout and leaves the tool running", function()
        EditMode.nudgeFrame = nudgeWith(false, true)

        EditMode:HandleEscape()

        assert.equals(1, flyoutClosed)
        assert.equals(0, closed)
        assert.equals(0, exited)
    end)

    -- The decoy. Without it, a handler that closed the flyout unconditionally
    -- passes the case above and Escape never exits again.
    it("exits when both layers are closed", function()
        EditMode.nudgeFrame = nudgeWith(false, false)

        EditMode:HandleEscape()

        assert.equals(0, flyoutClosed)
        assert.equals(1, exited)
    end)

    -- The layers are exclusive by construction, so this pins which one the
    -- handler reaches for rather than a state the user can produce. It fails
    -- an implementation that tests the flyout first, which would close the
    -- wrong thing the day the exclusion is broken.
    it("closes the list first when both somehow report open", function()
        EditMode.nudgeFrame = nudgeWith(true, true)

        EditMode:HandleEscape()

        assert.equals(1, closed)
        assert.equals(0, flyoutClosed)
        assert.equals(0, exited)
    end)

    -- The keyboard-propagation flag lives on the frame, not on the key event,
    -- so once Escape can be consumed WITHOUT tearing the handler down, only the
    -- handler itself can re-open it. HandleEscape cannot see any of this: the
    -- defect that shipped was entirely in the closure around it, and left every
    -- later keypress swallowed, movement included.
    describe("keyboard propagation", function()
        local escapeFrame, propagate, focus, nudged, nudgeArgs, nudgeResult
        local secretChecks

        -- Headlessly there is no real secret, so this stands in for one: the
        -- only thing the handler is allowed to do with it is hand it to
        -- issecretvalue, and any other use would be a truth test.
        local SECRET = {}

        local function press(key)
            escapeFrame:GetScript("OnKeyDown")(escapeFrame, key)
        end

        -- Focus is whatever holds the keyboard, KE's frames or another addon's.
        local function focusable(visible)
            return { IsVisible = function() return visible end }
        end

        before_each(function()
            EditMode:SetupEscapeHandler()
            escapeFrame = EditMode.escapeFrame
            propagate = nil
            escapeFrame.SetPropagateKeyboardInput = function(_, value)
                propagate = value
            end

            -- These three are read live at press time, so a case can set them
            -- in its own body.
            focus = nil
            _G.GetCurrentKeyBoardFocus = function() return focus end

            secretChecks = {}
            _G.issecretvalue = function(value)
                secretChecks[#secretChecks + 1] = value
                return value == SECRET
            end

            nudged, nudgeArgs, nudgeResult = 0, nil, true
            EditMode.NudgeSelectedElement = function(_, dx, dy)
                nudged = nudged + 1
                nudgeArgs = { dx, dy }
                return nudgeResult
            end
        end)

        -- Both halves, or the case is satisfied by a handler that consumes the
        -- key and then does nothing with it.
        it("consumes the Escape it acts on, and acts on it", function()
            EditMode.nudgeFrame = nudgeWithList(true)

            press("ESCAPE")

            assert.is_false(propagate)
            assert.equals(1, closed)
            assert.equals(0, exited)
        end)

        -- The closure must reach the WHOLE decision, not just the layer that
        -- happens to be on top: wire it to either branch alone and the case
        -- above still passes.
        it("exits through the same key when no list is open", function()
            EditMode.nudgeFrame = nudgeWithList(false)

            press("ESCAPE")

            assert.is_false(propagate)
            assert.equals(0, closed)
            assert.equals(1, exited)
        end)

        it("lets the next key through after a consumed Escape", function()
            EditMode.nudgeFrame = nudgeWithList(true)

            press("ESCAPE")
            press("W")

            assert.is_true(propagate)
        end)

        -- The propagation call is restricted in combat, and the combat auto-exit
        -- reaches this frame while still in lockdown. Touching it there is a
        -- blocked action, so the handler must do nothing at all.
        it("touches nothing in combat", function()
            inCombat = true
            EditMode.nudgeFrame = nudgeWithList(true)

            press("ESCAPE")

            assert.is_nil(propagate)
            assert.equals(0, closed)
            assert.equals(0, exited)
        end)

        it("never consumes a key it does not act on", function()
            EditMode.nudgeFrame = nudgeWithList(true)

            press("W")

            assert.is_true(propagate)
            assert.equals(0, closed)
            assert.equals(0, exited)
        end)

        -- Case 1 and case 2 differ in axis, in sign, and in modifier, so a
        -- hardcoded direction or a hardcoded modifier fails one of them.
        it("consumes an arrow that moved something", function()
            press("UP")

            assert.is_false(propagate)
            assert.equals(1, nudged)
            assert.same({ 0, 1 }, nudgeArgs)
        end)

        it("hands back an arrow that moved nothing", function()
            ctrlDown = true
            nudgeResult = false

            press("LEFT")

            assert.is_true(propagate)
            assert.equals(1, nudged)
            assert.same({ -10, 0 }, nudgeArgs)
        end)

        -- The flag assertion is the point: an implementation that returned
        -- before re-opening the flag passes on the nudge count alone, and its
        -- symptom is the NEXT key vanishing.
        it("leaves the arrows to a focused field", function()
            focus = focusable(true)

            press("UP")

            assert.equals(0, nudged)
            assert.is_true(propagate)
        end)

        -- The existing combat case presses only Escape, so without this an
        -- arrow branch could bypass the combat guard with everything else green.
        it("touches nothing in combat on an arrow either", function()
            inCombat = true

            press("UP")

            assert.is_nil(propagate)
            assert.equals(0, nudged)
        end)

        it("nudges when the focused field is not visible", function()
            focus = focusable(false)

            press("DOWN")

            assert.equals(1, nudged)
            assert.same({ 0, -1 }, nudgeArgs)
        end)

        -- The focus guard is scoped to arrows: Escape still backs out.
        it("still exits on Escape while a field is focused", function()
            focus = focusable(true)
            EditMode.nudgeFrame = nudgeWithList(false)

            press("ESCAPE")

            assert.equals(1, exited)
        end)

        -- Headlessly a secret is a table, and truth-testing a table never
        -- throws -- it is merely truthy. So the reversed order
        -- `visible or issecretvalue(visible)` routes correctly here and still
        -- throws in game. `or` short-circuits, so the reversed order never
        -- calls issecretvalue at all: asserting the call is what separates
        -- them. This proves invocation, not usage.
        it("asks whether the visibility is secret before reading it", function()
            focus = focusable(SECRET)

            press("UP")

            assert.equals(0, nudged)
            assert.is_true(propagate)
            assert.same({ SECRET }, secretChecks)
        end)
    end)
end)
