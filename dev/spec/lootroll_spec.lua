-- Modules/Skinning/LootRoll.lua -- the legacy CENTER -> BOTTOM conversion.
--
-- Why it exists: GroupLootContainer_Update sets the container's height to
-- reservedSize * (number of rolls) and anchors each roll relative to the
-- container's BOTTOM. Under a CENTER anchor the bottom edge moves every time
-- a roll is added, so every roll already on screen jumps. Anchoring the
-- bottom pins the first roll and lets the stack grow upward. A saved CENTER
-- value is converted rather than ignored, so an existing position does not
-- move on upgrade.

local L = require("dev.spec._ke_loader")

describe("LootRoll ApplyPosition", function()
    local LR, container

    -- Records the last SetPoint the module applied to the container.
    local function makeContainer(height, parent)
        return {
            _points = {},
            GetHeight = function(self) return height end,
            GetParent = function(self) return parent end,
            SetParent = function(self, p) self._parent = p end,
            ClearAllPoints = function(self) self._points = {} end,
            SetPoint = function(self, point, rel, relPoint, x, y)
                self._points[#self._points + 1] =
                    { point = point, relPoint = relPoint, x = x, y = y }
            end,
        }
    end

    before_each(function()
        LR, container = L.loadLootRoll()
    end)

    -- POSITIVE CONTROL. Without it, an ApplyPosition that returned early and
    -- never positioned anything would satisfy every assertion below.
    it("applies a saved BOTTOM anchor unchanged", function()
        LR.db = { Reposition = true, Position =
            { Point = "BOTTOM", RelPoint = "CENTER", X = 12, Y = 205 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        local p = LR._lastPoint()
        assert.equal("BOTTOM", p.point)
        assert.equal(12, p.x)
        assert.equal(205, p.y)
    end)

    it("converts a legacy CENTER anchor to BOTTOM and shifts y by half the height", function()
        LR.db = { Reposition = true, Position =
            { Point = "CENTER", RelPoint = "CENTER", X = 0, Y = 250 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        local p = LR._lastPoint()
        assert.equal("BOTTOM", p.point)
        assert.equal(210, p.y)   -- 250 - 80/2
    end)

    it("does not touch the db when it converts", function()
        -- The conversion is presentational. Writing it back would make the
        -- GUI's Y slider jump under the user on the next page open.
        LR.db = { Reposition = true, Position =
            { Point = "CENTER", RelPoint = "CENTER", X = 0, Y = 250 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        assert.equal("CENTER", LR.db.Position.Point)
        assert.equal(250, LR.db.Position.Y)
    end)

    it("does not position the container when Reposition is off", function()
        LR.db = { Reposition = false, Position =
            { Point = "BOTTOM", RelPoint = "CENTER", X = 0, Y = 205 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        assert.is_nil(LR._lastPoint())
    end)
end)

describe("LootRoll RollBar_Get", function()
    local LR

    before_each(function()
        LR = L.loadLootRollBars()
    end)

    -- POSITIVE CONTROL: the indexed form must actually create bars, or the
    -- free-bar assertions below would pass against an empty pool.
    it("creates a bar on demand for an index", function()
        local bar = LR:RollBar_Get(1)
        assert.is_table(bar)
        assert.equal(1, #LR.RollBars)
        assert.equal(bar, LR:RollBar_Get(1))   -- same bar, not a second one
    end)

    it("hands out a bar with no rollID when called with no index", function()
        LR:RollBar_Get(1)
        LR:RollBar_Get(2)
        LR.RollBars[1].rollID = 42
        assert.equal(LR.RollBars[2], LR:RollBar_Get())
    end)

    it("returns nil when every bar is busy", function()
        -- The caller queues the roll in waitingRolls on nil. Returning a
        -- busy bar instead would silently drop an in-flight roll.
        LR:RollBar_Get(1)
        LR.RollBars[1].rollID = 42
        assert.is_nil(LR:RollBar_Get())
    end)

    it("treats the preview sentinel as busy", function()
        -- ShowPreview parks the string "PREVIEW" in rollID precisely so a
        -- real roll cannot steal a bar whose buttons have mouse disabled.
        LR:RollBar_Get(1)
        LR.RollBars[1].rollID = "PREVIEW"
        assert.is_nil(LR:RollBar_Get())
    end)
end)

-- The preview must neutralize EVERY roll button, not most of them.
--
-- Found in game 2026-07-31: the reference lists four button keys in
-- previewButtons while CreateRollButton makes five, so Pass stayed
-- mouse-enabled during a preview and clicking it called
-- RollOnLoot("PREVIEW", 0) -- the sentinel rollID reaching the real API.
-- The two lists are file-locals, so this lifts each off the function that
-- closes over it rather than re-declaring the expected set here: a test
-- carrying its own copy of the button names would still pass if a sixth
-- button were added and left out of both.
describe("LootRoll preview button coverage", function()
    local function upvalue(fn, want)
        local i = 1
        while true do
            local name, value = debug.getupvalue(fn, i)
            if not name then return nil end
            if name == want then return value end
            i = i + 1
        end
    end

    it("neutralizes every button CreateRollButton makes", function()
        local LR = L.loadLootRollBars()
        local preview = upvalue(LR.ShowPreview, "previewButtons")
        local rollTypes = upvalue(LR.RollBars_Layout, "rollTypes")

        -- Positive controls: both seams must actually resolve, or every
        -- assertion below would pass vacuously against a nil table.
        assert.is_table(preview)
        assert.is_table(rollTypes)
        assert.is_true(#preview > 0)

        local neutralized = {}
        for _, key in ipairs(preview) do neutralized[key] = true end

        for _, key in pairs(rollTypes) do
            assert.is_true(neutralized[key],
                "roll button '" .. key .. "' is never mouse-disabled during preview")
        end
    end)

    it("restores exactly what it neutralized", function()
        -- ShowPreview and HidePreview must walk the SAME list, or a button
        -- disabled for the preview would stay dead for the next real roll.
        local LR = L.loadLootRollBars()
        assert.equal(upvalue(LR.ShowPreview, "previewButtons"),
                     upvalue(LR.HidePreview, "previewButtons"))
    end)
end)
