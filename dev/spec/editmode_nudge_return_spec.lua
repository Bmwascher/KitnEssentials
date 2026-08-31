-- Tier 1: refusal rule. This return value is the whole basis of the key
-- handler's decision to swallow a keypress or hand it back, and it fails
-- silently: the symptom of a wrong answer is a camera that stops turning,
-- which nobody would connect to a nudge function.
local L = require("dev.spec._ke_loader")

describe("EditMode:NudgeSelectedElement return value", function()
    local KE, EditMode, saved

    local function element(position)
        return {
            key = "el",
            getPosition = function() return position end,
            setPosition = function(p) saved = p end,
        }
    end

    before_each(function()
        KE = L.loadGlobals()
        EditMode = L.loadEditMode(KE)
        -- The no-selection refusal tells the player what to do, which lands in
        -- the busted output as a stray chat line. Silenced here, not in the
        -- module: the message is correct in game.
        KE.Print = function() end
        saved = nil
        -- Everything past the setter is frame and GUI work this rule does not
        -- depend on, so it is stubbed rather than simulated.
        EditMode.UpdateNudgeFrameInfo = function() end
        EditMode.overlayFrames = {}
    end)

    it("returns false with nothing selected", function()
        EditMode.selectedElementKey = nil
        assert.is_false(EditMode:NudgeSelectedElement(1, 0))
        assert.is_nil(saved)
    end)

    it("returns false when the selection is not in the registry", function()
        EditMode.selectedElementKey = "gone"
        EditMode.registeredElements = {}
        assert.is_false(EditMode:NudgeSelectedElement(1, 0))
        assert.is_nil(saved)
    end)

    it("returns false when the position cannot be read", function()
        EditMode.selectedElementKey = "el"
        EditMode.registeredElements = { el = element(nil) }
        assert.is_false(EditMode:NudgeSelectedElement(1, 0))
        assert.is_nil(saved)
    end)

    -- The arrow keys reach the selected element whenever nothing is focused,
    -- and a drag both selects and clears focus. Without this the keypress is
    -- written, silently overwritten at release, and leaves the read-out
    -- describing a position that is not the one being saved.
    it("returns false while the selected element is being dragged", function()
        EditMode.selectedElementKey = "el"
        EditMode.registeredElements = {
            el = element({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                           XOffset = 5, YOffset = 5 }),
        }
        EditMode.overlayFrames = { el = { isDragging = true } }

        assert.is_false(EditMode:NudgeSelectedElement(1, 0))
        assert.is_nil(saved)
    end)

    -- The decoy that gives the case above its meaning: an overlay that exists
    -- and is not dragging must not be refused.
    it("still nudges when the overlay exists and is idle", function()
        EditMode.selectedElementKey = "el"
        EditMode.registeredElements = {
            el = element({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                           XOffset = 5, YOffset = 5 }),
        }
        EditMode.overlayFrames = { el = { isDragging = false } }

        assert.is_true(EditMode:NudgeSelectedElement(1, 0))
        assert.equals(6, saved.XOffset)
    end)

    -- The case the narrow wording answers wrongly. A drag on one element while
    -- a different element is selected is what the wheel and the right-button
    -- chords make reachable: they select the box under the cursor, which is not
    -- always the box being dragged.
    it("returns false while a DIFFERENT element is being dragged", function()
        EditMode.selectedElementKey = "el"
        EditMode.registeredElements = {
            el = element({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                           XOffset = 5, YOffset = 5 }),
        }
        EditMode.overlayFrames = {
            el = { isDragging = false },
            other = { isDragging = true },
        }

        assert.is_false(EditMode:NudgeSelectedElement(1, 0))
        assert.is_nil(saved)
    end)

    it("returns true and saves when it commits", function()
        EditMode.selectedElementKey = "el"
        EditMode.registeredElements = {
            el = element({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                           XOffset = 5, YOffset = 5 }),
        }
        assert.is_true(EditMode:NudgeSelectedElement(3, -2))
        assert.equals(8, saved.XOffset)
        assert.equals(3, saved.YOffset)
    end)
end)
