-- Healer Mana's fallback anchor: which frame name is used, what reads as
-- usable, and how the Fallback Frame text splits. Placement on a frame is
-- anchoring and stays an in-game check.
local L = require("dev.spec._ke_loader")

describe("HealerMana fallback anchor", function()
    it("picks the main frame, then listed names in order, then the screen", function()
        local HM = L.loadHealerMana()
        local function usableSet(...)
            local set = {}
            for i = 1, select("#", ...) do set[select(i, ...)] = true end
            return function(name) return set[name] == true end
        end
        local list = { "B3", "B2", "H" }
        local cases = {
            { name = "main usable", main = "B4", usable = usableSet("B4", "B3"), kind = "MAIN", pick = "B4" },
            { name = "first listed usable", main = "B4", usable = usableSet("B3", "B2"), kind = "FALLBACK", pick = "B3" },
            { name = "later listed usable", main = "B4", usable = usableSet("H"), kind = "FALLBACK", pick = "H" },
            { name = "none usable", main = "B4", usable = usableSet(), kind = "SCREEN", pick = nil },
            { name = "no main name", main = nil, usable = usableSet("B4", "B2"), kind = "FALLBACK", pick = "B2" },
        }
        for _, c in ipairs(cases) do
            local kind, pick = HM.PickAnchor(c.main, list, c.usable)
            assert.are.equal(c.kind, kind, c.name)
            assert.are.equal(c.pick, pick, c.name)
        end
    end)

    it("reads a shown frame with a point as usable, and a secret read as usable", function()
        local SECRET = {}
        local HM = L.loadHealerMana({ issecretvalue = function(v) return v == SECRET end })
        local cases = {
            { name = "shown with a point", visible = true, points = 1, want = true },
            { name = "hidden", visible = false, points = 1, want = false },
            { name = "no points", visible = true, points = 0, want = false },
            { name = "secret visibility", visible = SECRET, points = 0, want = true },
            { name = "secret point count", visible = false, points = SECRET, want = true },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want, HM.AnchorReadsUsable(c.visible, c.points), c.name)
        end
    end)

    it("splits the Fallback Frame text on commas and spaces, in order", function()
        local HM = L.loadHealerMana()
        local cases = {
            { name = "commas and spaces", text = "  B3, B2,,  H  ", want = { "B3", "B2", "H" } },
            { name = "spaces only", text = "B3 B2", want = { "B3", "B2" } },
            { name = "dotted name", text = "Parent.child", want = { "Parent.child" } },
            { name = "blank", text = "   ", want = {} },
            { name = "nil", text = nil, want = {} },
        }
        for _, c in ipairs(cases) do
            assert.are.same(c.want, HM.ParseFrameList(c.text), c.name)
        end
    end)

    it("counts a kind change or a fallback name change as a move, never a main name change", function()
        local HM = L.loadHealerMana()
        local cases = {
            { name = "nil held, main", held = nil, kind = "MAIN", pick = "B4", want = false },
            { name = "nil held, fallback", held = nil, kind = "FALLBACK", pick = "B3", want = true },
            { name = "main renamed", held = "MAIN", heldName = "B4", kind = "MAIN", pick = "B1", want = false },
            { name = "main to fallback", held = "MAIN", heldName = "B4", kind = "FALLBACK", pick = "B3", want = true },
            { name = "fallback renamed", held = "FALLBACK", heldName = "B2", kind = "FALLBACK", pick = "B3", want = true },
            { name = "fallback unchanged", held = "FALLBACK", heldName = "B2", kind = "FALLBACK", pick = "B2", want = false },
            { name = "fallback to screen", held = "FALLBACK", heldName = "B2", kind = "SCREEN", pick = nil, want = true },
            { name = "screen unchanged", held = "SCREEN", heldName = nil, kind = "SCREEN", pick = nil, want = false },
            { name = "screen to main", held = "SCREEN", heldName = nil, kind = "MAIN", pick = "B4", want = true },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want, HM.ChoiceDiffers(c.held, c.heldName, c.kind, c.pick), c.name)
        end
    end)
end)
