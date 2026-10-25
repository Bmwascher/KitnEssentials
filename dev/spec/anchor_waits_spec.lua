-- Tier 1: a guard rule KE invented. A frame placed on a Select Frame name whose
-- first part is not a global yet waits for that name's announce, and a broken
-- wait leaves it on the screen with no message. The fakes are static region
-- tables like unsafe_anchor_spec.lua's, plus a note of the last SetPoint,
-- read back through GetNumPoints and GetPoint; no Blizzard subsystem is faked.
local L = require("dev.spec._ke_loader")

local function region()
    return {
        [0] = newproxy(),
        GetParent = function() return nil end,
        GetNumPoints = function() return 0 end,
        GetPoint = function() return nil end,
        IsObjectType = function(_, objectType) return objectType == "Frame" end,
        IsForbidden = function() return false end,
    }
end

local function placed()
    local f = region()
    f.ClearAllPoints = function(self) self.point, self.anchor, self.relativePoint = nil, nil, nil end
    f.SetPoint = function(self, point, relativeTo, relativePoint)
        self.point, self.anchor, self.relativePoint = point, relativeTo, relativePoint
    end
    f.GetNumPoints = function(self) return self.point and 1 or 0 end
    f.GetPoint = function(self) return self.point, self.anchor, self.relativePoint end
    f.SetParent = function() end
    f.SetFrameStrata = function() end
    return f
end

describe("late anchor targets", function()
    local KE

    setup(function()
        KE = L.loadGlobals()
        KE.SnapFrameToPixels = function() end
    end)

    after_each(function()
        _G.KE_SpecLateTarget, _G.KE_SpecOtherTarget = nil, nil
    end)

    it("waits on a missing root, moves on its announce, and stops waiting once placed elsewhere", function()
        local pos = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 0 }
        local onLate = { anchorFrameType = "SELECTFRAME", ParentFrame = "KE_SpecLateTarget" }
        local other, seat = region(), region()
        _G.KE_SpecOtherTarget = other
        local rows = {
            { name = "waiting", frame = placed(), onTarget = true },
            { name = "moved to another anchor type", frame = placed(),
              thenPlace = { anchorFrameType = "UIPARENT" }, want = _G.UIParent },
            { name = "moved onto a frame that exists", frame = placed(),
              thenPlace = { anchorFrameType = "SELECTFRAME", ParentFrame = "KE_SpecOtherTarget" }, want = other },
            { name = "seated by another path", frame = placed(), thenSeat = seat, want = seat },
            { name = "saved pair edited with no placement", frame = placed(), onTarget = true,
              pos = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 0 }, thenEdit = "TOP" },
        }
        for _, row in ipairs(rows) do
            local rowPos = row.pos or pos
            KE:ApplyFramePosition(row.frame, rowPos, onLate)
            assert.equal(_G.UIParent, row.frame.anchor, row.name .. ": a missing root falls back to the screen")
            if row.thenPlace then KE:ApplyFramePosition(row.frame, rowPos, row.thenPlace) end
            if row.thenSeat then
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOP", row.thenSeat, "BOTTOM", 0, 0)
            end
            if row.thenEdit then rowPos.AnchorFrom, rowPos.AnchorTo = row.thenEdit, row.thenEdit end
        end

        local target = region()
        _G.KE_SpecLateTarget = target
        KE:AnnounceAnchorTarget("KE_SpecLateTarget")

        for _, row in ipairs(rows) do
            assert.equal(row.onTarget and target or row.want, row.frame.anchor, row.name)
        end
    end)
end)
