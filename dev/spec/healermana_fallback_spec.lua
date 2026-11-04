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

    it("writes the held set, main as given and fallback as a copy, or leaves both", function()
        local HM = L.loadHealerMana()
        local function copy(t)
            return { AnchorFrom = t.AnchorFrom, AnchorTo = t.AnchorTo, XOffset = t.XOffset, YOffset = t.YOffset }
        end
        local MAIN = { AnchorFrom = "TOPLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 0, YOffset = -1 }
        local MOVED = { AnchorFrom = "TOP", AnchorTo = "BOTTOM", XOffset = 7, YOffset = -5 }
        local cases = {
            { name = "main", kind = nil, pos = "moved", wrote = true, stored = "Position" },
            { name = "fallback", kind = "FALLBACK", pos = "moved", wrote = true, stored = "FallbackPosition" },
            { name = "unset fallback handed the main table", kind = "FALLBACK", pos = "main", wrote = true },
            { name = "unset fallback handed the main values", kind = "FALLBACK", pos = "mainValues", wrote = true },
            { name = "screen center", kind = "SCREEN", pos = "moved", wrote = false },
            { name = "held frame lost its rect", kind = "FALLBACK", pos = "moved", wrote = false,
                unmeasurable = true },
        }
        for _, c in ipairs(cases) do
            HM.db.Position = copy(MAIN)
            HM.db.FallbackPosition = nil
            HM.partyAnchorKind = c.kind
            -- The rect read is a frame read; the case covers the refusal it feeds.
            HM.HeldFrameMeasurable = function() return not c.unmeasurable end
            local pos = (c.pos == "main" and HM.db.Position)
                or (c.pos == "mainValues" and copy(MAIN)) or copy(MOVED)
            assert.are.equal(c.wrote, HM:WritePartyPosition(pos), c.name)
            assert.are.same(c.stored == "Position" and MOVED or MAIN, HM.db.Position, c.name)
            if c.stored == "FallbackPosition" then
                assert.are.same(MOVED, HM.db.FallbackPosition, c.name)
                assert.is_false(rawequal(HM.db.FallbackPosition, pos), c.name)
            else
                assert.is_nil(HM.db.FallbackPosition, c.name)
            end
        end
    end)

    it("holds a new frame back in combat and nothing else", function()
        local HM = L.loadHealerMana()
        local cases = {
            { name = "new frame in combat", held = "FALLBACK", heldName = "B3", kind = "FALLBACK", pick = "B2",
                combat = true, want = true },
            { name = "new frame out of combat", held = "FALLBACK", heldName = "B3", kind = "FALLBACK", pick = "B2",
                combat = false, want = false },
            { name = "same frame in combat", held = "FALLBACK", heldName = "B3", kind = "FALLBACK", pick = "B3",
                combat = true, want = false },
            { name = "main renamed in combat", held = "MAIN", heldName = "B4", kind = "MAIN", pick = "B1",
                combat = true, want = false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want, HM.DefersChoice(c.held, c.heldName, c.kind, c.pick, c.combat), c.name)
        end
    end)
end)
