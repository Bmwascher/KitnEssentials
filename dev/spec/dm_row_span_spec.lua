-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_row_span_spec.lua                           ║
-- ║  The height a list of meter rows needs.                  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- DM.RowSpan is arithmetic every window, dock and detail height reads. A slip
-- shows only as a changed height at today's settings or a last row cut by one
-- pixel, so it gets a case. Frame layout itself stays an in-game check.
local L = require("dev.spec._ke_loader")

describe("DM.RowSpan", function()
    it("keeps the trailing gap for a positive spacing and adds back the overhang for a negative one", function()
        local DM = L.loadDMCore()
        local cases = {
            { name = "positive spacing, today's height", count = 10, stride = 17, spacing = 1, want = 170 },
            { name = "spacing -1, one pixel added", count = 10, stride = 15, spacing = -1, want = 151 },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, DM.RowSpan(c.count, c.stride, c.spacing), c.name)
        end
    end)
end)
