-- Tier 1: a refusal rule. Edit Mode measures a drag's offsets against the
-- anchor the module's placement really uses; a wrong answer saves offsets the
-- display jumps by on release. The region fakes are static tables answering
-- GetParent, GetNumPoints, GetPoint, IsObjectType and IsForbidden with fixed
-- values, not a stateful Blizzard fake.
local L = require("dev.spec._ke_loader")

-- A widget carrying its handle at index 0; each extra argument is the
-- relativeTo of one anchor point.
local function region(isFrame, parent, ...)
    local points = { ... }
    return {
        [0] = newproxy(),
        GetParent = function() return parent end,
        GetNumPoints = function() return #points end,
        GetPoint = function(_, i) return "CENTER", points[i], "CENTER", 0, 0 end,
        IsObjectType = function(_, objectType) return isFrame and objectType == "Frame" end,
        IsForbidden = function() return false end,
    }
end

describe("edit mode drag parent", function()
    local EffectiveDragParent

    setup(function()
        local KE = L.loadGlobals()
        EffectiveDragParent = L.loadEditMode(KE)._EffectiveDragParent
    end)

    it("measures a drag against the anchor placement uses", function()
        local frame = region(true, nil)
        local child = region(true, frame)
        local other = region(true, nil)
        local text = region(false, nil)
        local anchored = region(true, nil, text)
        local rows = {
            { name = "dependent anchor", frame = frame, parent = child, want = _G.UIParent },
            { name = "independent frame", frame = frame, parent = other, want = other },
            { name = "text the frame is anchored to", frame = anchored, parent = text, want = text },
            { name = "text the frame is not anchored to", frame = frame, parent = text, want = _G.UIParent },
        }
        for _, row in ipairs(rows) do
            assert.equal(row.want, EffectiveDragParent(row.frame, row.parent), row.name)
        end
    end)

    it("restores a cancel against the drag's answer, not the frame's points", function()
        local frame = region(true, nil)
        local text = region(false, nil)
        assert.equal(text, EffectiveDragParent(frame, text, text))
        assert.equal(_G.UIParent, EffectiveDragParent(frame, text, _G.UIParent))
    end)
end)
