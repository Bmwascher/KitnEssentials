-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_sample_rows_spec.lua                        ║
-- ║  Damage Meter settings-preview sample rows.              ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- WHY THIS EARNS A SPEC: the sample rows branch on the window and on readable
-- amounts, and a sample bar must never open a detail panel; each breaks
-- silently. Loads the REAL Window.lua (L.loadDMClock) for the arithmetic and
-- the REAL Detail.lua on top of it for the click refusal. Secrecy is declared
-- ({ __secret = true }), never real.
local L = require("dev.spec._ke_loader")
local helpers = require("dev.spec._helpers")

local SECRET = { __secret = true }

describe("Damage Meter sample rows", function()
    it("continues below the last real bar, keeps a count of 1 drawable, and refuses unreadable amounts", function()
        local DM = L.loadDMClock()
        assert(DM.SampleRows, "Window.lua did not expose DM.SampleRows")
        local cases = {
            { name = "a rate meter continues below the last bar", count = 3, last = 1000, max = 5000, n = 4, scaled = true },
            -- Past the sixth row 0.9^k drops under 0.5, so the label rounds to 0.
            { name = "a count of 1 still draws, shorter each row", count = 1, last = 1, max = 3, n = 8, scaled = true },
            { name = "no real rows take the fixed list", count = 0, n = 5, fixed = true },
            { name = "a Deaths window takes the fixed list", count = 2, deaths = true, last = 1, max = 1, n = 5, fixed = true },
            { name = "a secret last amount shows none", count = 2, last = SECRET, max = 10, n = 3 },
            { name = "a secret maximum shows none", count = 2, last = 5, max = SECRET, n = 3 },
            { name = "a zero amount shows none", count = 2, last = 0, max = 10, n = 3 },
            { name = "no room shows none", count = 2, last = 5, max = 10, n = 0 },
        }
        for _, c in ipairs(cases) do
            local rows, fillMax = DM.SampleRows({}, c.n, c.count, c.deaths, c.last, c.max)
            if c.scaled then
                assert.equals(c.max, fillMax, c.name .. ": fills against the real maximum")
                local above = c.last
                for k = 1, c.n do
                    local f = rows[k].fillAmount
                    assert.is_true(f > 0 and f < above, c.name .. ": row " .. k .. " shorter than the one above")
                    assert.equals(math.floor(f + 0.5), rows[k].totalAmount, c.name .. ": label rounds the fill")
                    above = f
                end
            elseif c.fixed then
                assert.is_true(rows ~= nil and rows[1].isSample == true and rows[1].fillAmount == nil, c.name)
                assert.equals(rows[1].totalAmount, fillMax, c.name .. ": fills against its own maximum")
            else
                assert.is_nil(rows, c.name)
            end
        end
    end)

    it("counts the slots from the dock rect and leaves none below a full window", function()
        local DM = L.loadDMClock()
        assert(DM.SampleFit, "Core.lua did not expose DM.SampleFit")
        local cases = {
            { name = "from the dock rect less the header band", W = { _dockRect = { h = 100 }, _headerH = 20, _snapStride = 17 }, fit = 5 },
            { name = "from the body height before a layout", W = { _snapStride = 17 }, viewH = 34, fit = 2 },
            { name = "capped at the bar pool", W = { _dockRect = { h = 5000 }, _headerH = 20, _snapStride = 17 }, fit = 40 },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.fit, DM.SampleFit(c.W, c.viewH), c.name)
        end
        assert.equals(2, DM.SampleCount(5, 3), "room below the real rows")
        assert.equals(0, DM.SampleCount(5, 7), "never below 0")
    end)

    it("opens no detail for a sample bar and goes on for a real one", function()
        for _, sample in ipairs({ true, false }) do
            local DM, KE = L.loadDMClock()
            helpers.loadModule("Modules/Skinning/DamageMeter/Detail.lua", KE)
            local reached = 0
            DM.HideHoverTip = function() reached = reached + 1 end
            DM.ResolveWindowConfig = function() error("past the guard") end
            local bar = { win = { idx = 1 }, _sample = sample or nil }
            local ok = pcall(DM.OpenDetail, DM, bar, "LeftButton")
            if sample then
                assert.is_true(ok, "sample: returns cleanly")
                assert.equals(0, reached, "sample: nothing after the guard runs")
            else
                assert.equals(1, reached, "real: goes on past the guard")
            end
        end
    end)

    -- The recording C_Timer keeps next-frame work and delayed timers apart, so a
    -- row runs the frames of each step, then fires the timers at the end.
    it("redraws once after the last resize step, only with the preview on, never during a drag", function()
        local frames, timers = {}, {}
        local DM = L.loadDMDock({ C_Timer = { After = function(delay, fn)
            if delay == 0 then frames[#frames + 1] = fn else timers[#timers + 1] = fn end
        end } })
        assert(DM.RequestPreviewRedraw, "Dock.lua did not expose DM.RequestPreviewRedraw")
        local ticks, inCombat = 0, false
        local savedICL = _G.InCombatLockdown
        finally(function() _G.InCombatLockdown = savedICL end)
        _G.InCombatLockdown = function() return inCombat end
        DM.enabled = true
        DM.LayoutDock, DM.UpdateBackdrop = function() end, function() end
        DM.Tick = function() ticks = ticks + 1 end
        local function runAll(q)
            local i = 1
            while q[i] do q[i]() i = i + 1 end
            for k = #q, 1, -1 do q[k] = nil end
        end
        local cases = {
            { name = "three slider steps redraw once", preview = true, steps = 3, want = 1 },
            { name = "a drag's frames set no timer", preview = true, drag = true, steps = 3, want = 0 },
            { name = "a drag's release redraws once", preview = true, drag = true, release = true, steps = 3, want = 1 },
            { name = "a drag begun before the timer fires stops its redraw", preview = true, steps = 1, dragAfter = true, want = 0 },
            { name = "the preview off sets no timer", preview = false, steps = 3, want = 0 },
            { name = "combat when the timer fires redraws nothing", preview = true, steps = 1, combat = true, want = 0 },
        }
        for _, c in ipairs(cases) do
            ticks, inCombat = 0, false
            DM._guiPreview, DM._resizeDragging = c.preview, nil
            local owner = {}
            if c.drag then DM:BeginResizeDrag(owner) end
            for _ = 1, c.steps do
                DM:RefreshDock()
                runAll(frames)
            end
            if c.drag or not c.preview then
                assert.equals(0, #timers, c.name .. ": no timer yet")
            end
            if c.dragAfter then DM:BeginResizeDrag(owner) end
            if c.release then
                DM:EndResizeDrag({})
                assert.equals(owner, DM._resizeDragging, c.name .. ": another frame's stop leaves the drag")
                DM:EndResizeDrag(owner)
            end
            inCombat = c.combat or false
            runAll(timers)
            assert.equals(c.want, ticks, c.name)
        end
    end)
end)
