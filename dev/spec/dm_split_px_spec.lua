-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_split_px_spec.lua                           ║
-- ║  Pixel split arithmetic for the Sizing card (Dock.lua).  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/Skinning/DamageMeter/Dock.lua headlessly (L.loadDMDock)
-- and drives DM.SplitPxRange, DM.SplitPxSnap and DM.SplitPxToRatios with an
-- explicit grid step. Each pane draws PixelSnap(K * ratio), K = exact /
-- pairRatio, which is floor(K * ratio / grid + 0.5) * grid, so the split rows
-- assert the panes LayoutDock would draw. Grid 0.8 is a UI scale off the
-- perfect one. Column and row gaps pass the same numbers, so one table covers
-- both.
local L = require("dev.spec._ke_loader")

describe("Split pixel arithmetic", function()
    it("keeps the floor on the grid, never inverts, draws the asked size and keeps the drawn pair", function()
        local DM = L.loadDMDock()
        assert(DM and DM.SplitPxToRatios, "loadDMDock did not expose DM.SplitPxToRatios")
        local ranges = {
            { name = "two floors fit", drawn = 170, floor = 80, grid = 1, lo = 80, hi = 90 },
            { name = "a wide pair", drawn = 400, floor = 80, grid = 1, lo = 80, hi = 320 },
            { name = "an undersized pair splits at half", drawn = 150, floor = 80, grid = 1, lo = 75, hi = 75 },
            { name = "an odd undersized pair", drawn = 151, floor = 80, grid = 1, lo = 75, hi = 76 },
            { name = "two floors exactly fit on a 0.8 grid", drawn = 81.6, floor = 40.8, grid = 0.8, lo = 40.8, hi = 40.8 },
            { name = "a wide pair on a 0.8 grid", drawn = 160, floor = 40.8, grid = 0.8, lo = 40.8, hi = 119.2 },
            { name = "an undersized pair on a 0.8 grid", drawn = 80, floor = 40.8, grid = 0.8, lo = 40, hi = 40 },
            { name = "a pair with no size", drawn = 0, floor = 80, grid = 1, lo = 0, hi = 0 },
        }
        for _, c in ipairs(ranges) do
            local lo, hi = DM.SplitPxRange(c.drawn, c.floor, c.grid)
            assert.near(c.lo, lo, 1e-9, c.name .. ": lo")
            assert.near(c.hi, hi, 1e-9, c.name .. ": hi")
            assert.is_true(lo <= hi + 1e-9, c.name .. ": lo <= hi")
        end
        local snaps = {
            { name = "a whole number on grid 1", value = 150.4, lo = 80, hi = 320, grid = 1, want = 150 },
            { name = "below the floor clamps", value = 30, lo = 80, hi = 320, grid = 1, want = 80 },
            { name = "a whole number onto a 0.8 grid", value = 41, lo = 40.8, hi = 119.2, grid = 0.8, want = 40.8 },
            { name = "a collapsed range", value = 90, lo = 40.8, hi = 40.8, grid = 0.8, want = 40.8 },
        }
        for _, c in ipairs(snaps) do
            assert.near(c.want, DM.SplitPxSnap(c.value, c.lo, c.hi, c.grid), 1e-9, c.name)
        end
        local splits = {
            -- Width 200, both columns at ratio 1.
            { name = "drawn equals exact", px = 150, drawn = 400, exact = 400, pairRatio = 2, grid = 1 },
            -- Two 100.4 px panes draw 100 + 100.
            { name = "drawn one pixel below exact", px = 80, drawn = 200, exact = 200.8, pairRatio = 1.004, grid = 1 },
            -- Two 99.6 px panes draw 100 + 100.
            { name = "drawn one pixel above exact", px = 120, drawn = 200, exact = 199.2, pairRatio = 0.996, grid = 1 },
            { name = "a row pair", px = 183, drawn = 300, exact = 300, pairRatio = 1, grid = 1 },
            -- Two 40.6 panes draw 40.8 + 40.8 on a 0.8 grid.
            { name = "drawn above exact on a 0.8 grid", px = 32, drawn = 81.6, exact = 81.2, pairRatio = 2, grid = 0.8 },
        }
        for _, c in ipairs(splits) do
            local a, b = DM.SplitPxToRatios(c.px, c.drawn, c.exact, c.pairRatio)
            local K = c.exact / c.pairRatio
            local function draw(v) return math.floor(v / c.grid + 0.5) * c.grid end
            assert.near(c.px, draw(K * a), 1e-9, c.name .. ": first pane")
            assert.near(c.drawn - c.px, draw(K * b), 1e-9, c.name .. ": second pane")
        end
        assert.is_nil(DM.SplitPxToRatios(100, 200, 0, 2), "a pair with no exact size")
    end)
end)
