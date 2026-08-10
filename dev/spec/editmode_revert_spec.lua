-- Tier 1: invented state handling whose two failure modes are both silent, and
-- both depend on how the module under the element happens to save. A smoke pass
-- on one element proves nothing about the other forty-one.
local L = require("dev.spec._ke_loader")

describe("EditMode revert", function()
    local KE, EditMode

    -- TWO module styles, because the two silent failures need different ones
    -- and a single mock can only catch one of them. This first style edits its
    -- own live table in place and never keeps what it is handed.
    local function inPlaceElement(key)
        local live = { AnchorFrom = "CENTER", AnchorTo = "CENTER",
                       XOffset = 10, YOffset = 20 }
        return {
            key = key,
            guiPath = "CombatTimer",
            live = live,
            getPosition = function() return live end,
            setPosition = function(pos)
                live.AnchorFrom = pos.AnchorFrom
                live.AnchorTo = pos.AnchorTo
                live.XOffset = pos.XOffset
                live.YOffset = pos.YOffset
            end,
        }
    end

    -- The second style ADOPTS the table it is handed as its own storage, and
    -- edits through it afterwards. Both halves are needed: adopting alone
    -- corrupts nothing, and the later edit is what writes through into whatever
    -- was adopted. Modules that save a position table wholesale and then nudge
    -- it in place behave exactly this way.
    local function adoptingElement(key)
        local live = { AnchorFrom = "CENTER", AnchorTo = "CENTER",
                       XOffset = 10, YOffset = 20 }
        return {
            key = key,
            guiPath = "CombatTimer",
            getPosition = function() return live end,
            setPosition = function(pos) live = pos end,
            moveTo = function(x, y)
                live.XOffset = x
                live.YOffset = y
            end,
        }
    end

    before_each(function()
        KE = L.loadGlobals()
        EditMode = L.loadEditMode(KE)
        EditMode.positionSnapshots = {}
        EditMode.overlayFrames = {}
        EditMode.registeredElements = {}
    end)

    it("refuses an element it never snapshotted", function()
        EditMode.registeredElements.Timer = inPlaceElement("Timer")
        assert.is_false(EditMode:RevertElement("Timer"))
    end)

    -- The first silent failure. Holding the getter's table would make the
    -- snapshot follow every later move, and revert would restore the position
    -- the element is already in.
    it("copies the values rather than holding the getter's table", function()
        local el = inPlaceElement("Timer")
        EditMode.registeredElements.Timer = el
        EditMode:SnapshotElementPosition("Timer")

        el.setPosition({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                         XOffset = 99, YOffset = 99 })
        assert.equals(99, el.live.XOffset)

        assert.is_true(EditMode:RevertElement("Timer"))
        assert.equals(10, el.live.XOffset)
        assert.equals(20, el.live.YOffset)
    end)

    -- The second, and it needs the adopting style to be visible at all. Handing
    -- the snapshot straight to a setter that keeps it means the element's next
    -- move writes through into the snapshot, so the FIRST revert looks correct
    -- and only the second one is wrong.
    it("survives being reverted twice", function()
        local el = adoptingElement("Timer")
        EditMode.registeredElements.Timer = el
        EditMode:SnapshotElementPosition("Timer")

        el.moveTo(99, 99)
        EditMode:RevertElement("Timer")
        assert.equals(10, el.getPosition().XOffset)

        -- If the revert above handed the snapshot over, this writes 55 into it.
        el.moveTo(55, 55)
        assert.is_true(EditMode:RevertElement("Timer"))
        assert.equals(10, el.getPosition().XOffset)
        assert.equals(20, el.getPosition().YOffset)
    end)

    it("restores the anchors as well as the offsets", function()
        local el = inPlaceElement("Timer")
        EditMode.registeredElements.Timer = el
        EditMode:SnapshotElementPosition("Timer")

        el.setPosition({ AnchorFrom = "TOPLEFT", AnchorTo = "TOPLEFT",
                         XOffset = 1, YOffset = 1 })
        EditMode:RevertElement("Timer")
        assert.equals("CENTER", el.live.AnchorFrom)
        assert.equals("CENTER", el.live.AnchorTo)
    end)

    -- The pooled-frame trap. Re-adopting an overlay re-takes the snapshot, so
    -- reverting in a later session restores where the element sat when THAT
    -- session opened, not where it sat in an earlier one.
    it("re-snapshots on re-adoption rather than keeping the first one", function()
        local el = inPlaceElement("Timer")
        EditMode.registeredElements.Timer = el
        EditMode:SnapshotElementPosition("Timer")

        el.setPosition({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                         XOffset = 77, YOffset = 88 })
        EditMode:SnapshotElementPosition("Timer")

        el.setPosition({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                         XOffset = 5, YOffset = 5 })
        EditMode:RevertElement("Timer")
        assert.equals(77, el.live.XOffset)
        assert.equals(88, el.live.YOffset)
    end)
end)
