-- Tier 1: the own-scale drag conversion. An element that opts in drags in its
-- frame's own units; a wrong ratio moves the frame faster or slower than the
-- cursor and stores offsets it does not land on. The scale fakes are static
-- tables answering GetEffectiveScale with a fixed value.
local L = require("dev.spec._ke_loader")

local function scaled(value)
    return { GetEffectiveScale = function() return value end }
end

-- Any field read raises: the opt-out must not ask a frame for anything.
local unreadable = setmetatable({}, {
    __index = function() error("frame read without the opt-in") end,
})

describe("edit mode own-scale drag", function()
    local EditMode
    local SECRET = {}

    setup(function()
        local KE = L.loadGlobals({ issecretvalue = function(value) return value == SECRET end })
        EditMode = L.loadEditMode(KE)
    end)

    it("converts between UIParent, parent and frame units", function()
        local rows = {
            { name = "half-scale frame on UIParent", ui = 1, target = 0.5, parent = 1, k = 2, p = 2 },
            { name = "double-scale frame on UIParent", ui = 1, target = 2, parent = 1, k = 0.5, p = 0.5 },
            { name = "frame under a scaled parent", ui = 0.5, target = 0.25, parent = 1, k = 2, p = 4 },
            { name = "a secret scale refuses", ui = 1, target = SECRET, parent = 1 },
            { name = "a zero scale refuses", ui = 1, target = 0, parent = 1 },
            { name = "a missing scale refuses", ui = 1, target = nil, parent = 1 },
        }
        for _, row in ipairs(rows) do
            local k, p = EditMode._DragUnitRatios(true, scaled(row.ui), scaled(row.target), scaled(row.parent))
            assert.equal(row.k, k, row.name)
            assert.equal(row.p, p, row.name)
        end

        local context = {
            spacing = 32, originX = 960, originY = 540,
            candidatesX = { 10, 20 }, candidatesY = { 5 },
        }
        EditMode._ScaleSnapContext(context, 0.5)
        assert.same({
            spacing = 16, originX = 480, originY = 270,
            candidatesX = { 5, 10 }, candidatesY = { 2.5 },
            thresholdScale = 0.5,
        }, context)
    end)

    it("reads no scale and converts nothing for an element that does not opt in", function()
        local rows = {
            { name = "no ownScale field" },
            { name = "ownScale false", ownScale = false },
        }
        for _, row in ipairs(rows) do
            local k, p = EditMode._DragUnitRatios(row.ownScale, unreadable, unreadable, unreadable)
            assert.equal(1, k, row.name)
            assert.equal(1, p, row.name)
        end
    end)
end)
