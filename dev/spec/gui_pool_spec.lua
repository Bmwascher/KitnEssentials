-- Tier 2: the page-frame pools in GUI/GUIMain/GUI-Core.lua.
--
-- The guard, the key sweep, the ownership test and the release routing are
-- logic this addon invented, and each fails silently: a wrong answer reuses a
-- widget some page still drives, or leaks one the pool should have kept. The
-- guard and the sweep are pure and tested directly. The bookkeeping and
-- routing cases need objects that answer GetNumChildren/GetNumRegions and
-- take SetParent, because counting and reparenting ARE what the pool does;
-- fakeFrame holds only those counts and its parent.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

local function fakeFrame(children, regions)
    local f = { children = children, regions = regions }
    function f:GetNumChildren() return self.children end
    function f:GetNumRegions() return self.regions end
    function f:SetParent(parent) self.parent = parent end
    function f:GetParent() return self.parent end
    function f:IsObjectType(kind) return kind == "Frame" end
    function f:Show() end
    function f:Hide() end
    function f:SetAlpha() end
    function f:ClearAllPoints() end
    return f
end

describe("GUI-Core widget pools", function()
    local GUIFrame

    before_each(function()
        mock.install()
        _G.UIParent = CreateFrame()
        _G.KE_GUI_ORPHAN_COUNT = 0
        local KE = { Theme = { headerHeight = 32, borderSize = 1 }, Print = function() end }
        helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
        GUIFrame = KE.GUIFrame
    end)

    after_each(function()
        mock.reset()
        _G.KE_GUI_ORPHAN_COUNT = nil
    end)

    it("counts an object clean only when every owned frame matches its baseline and nothing holds it", function()
        local base = { 2, 9, 0, 1 }
        local cases = {
            { name = "all match",      measured = { 2, 9, 0, 1 }, busy = false, clean = true },
            { name = "a child added",  measured = { 3, 9, 0, 1 }, busy = false, clean = false },
            { name = "a region added", measured = { 2, 9, 0, 2 }, busy = false, clean = false },
            { name = "held busy",      measured = { 2, 9, 0, 1 }, busy = true,  clean = false },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.clean, GUIFrame.PoolIsClean(base, case.measured, case.busy), case.name)
        end
    end)

    it("sweeps added keys, restores replaced and deleted methods, and keeps the handle and pool keys", function()
        local handle = {}
        local setEnabled = function() end
        local updateHeight = function() end
        local obj = { [0] = handle, rows = {}, SetEnabled = setEnabled, UpdateHeight = updateHeight }
        local snapshot = { [0] = true, rows = true, SetEnabled = setEnabled, UpdateHeight = updateHeight }

        obj.SetEnabled = function() end
        obj.UpdateHeight = nil
        obj.kit = "a page's own field"
        obj._keBlocker = "a pool part"

        GUIFrame.PoolSweepKeys(obj, snapshot)

        assert.equals(handle, obj[0])
        assert.is_table(obj.rows)
        assert.equals(setEnabled, obj.SetEnabled)
        assert.equals(updateHeight, obj.UpdateHeight)
        assert.is_nil(obj.kit)
        assert.equals("a pool part", obj._keBlocker)
    end)

    it("routes a tracked child: releases pooled ones here, orphans foreign frames here, leaves the rest", function()
        local container = fakeFrame(0, 0)
        local elsewhere = fakeFrame(0, 0)
        local released
        local pool = { Release = function(_, obj) released = obj end }
        local cases = {
            { name = "pooled, here",          pooled = true,  parent = container, released = true,  orphaned = false },
            { name = "pooled, taken",         pooled = true,  parent = elsewhere, released = false, orphaned = false },
            { name = "foreign frame, here",   pooled = false, parent = container, released = false, orphaned = true },
            { name = "foreign frame, taken",  pooled = false, parent = elsewhere, released = false, orphaned = false },
            { name = "region, here",          region = true,  parent = container, released = false, orphaned = false },
        }
        for _, case in ipairs(cases) do
            released = nil
            _G.KE_GUI_ORPHAN_COUNT = 0
            local child = fakeFrame(0, 0)
            child.parent = case.parent
            if case.pooled then
                child._kePool = pool
                child._keState = "used"
            end
            if case.region then
                child.IsObjectType = function() return false end
            end

            GUIFrame:ReleaseTracked(child, container)

            assert.equals(case.released, released == child, case.name)
            assert.equals(case.orphaned, child.parent == nil, case.name)
            assert.equals(case.orphaned and 1 or 0, _G.KE_GUI_ORPHAN_COUNT, case.name)
        end
    end)

    it("hands a clean released object back advanced, ignores a double release, never reuses a retired one", function()
        local pool = GUIFrame:NewWidgetPool("spec", function(holder)
            local f = fakeFrame(0, 0)
            f.parent = holder
            f._keOwned = { f }
            return f
        end, function() end)
        local page = fakeFrame(0, 0)

        local first = pool:Acquire(page)
        pool:Release(first)
        pool:Release(first)
        assert.equals(1, #pool.free, "the second release did nothing")
        assert.equals(first, pool:Acquire(page))
        assert.equals(1, first._keGen)

        -- Something parented a frame to it while it was in use.
        first.children = 1
        pool:Release(first)
        assert.equals("retired", first._keState)
        assert.is_nil(first.parent)
        assert.equals(1, GUIFrame._poolStats.retired)
        assert.equals(1, _G.KE_GUI_ORPHAN_COUNT)

        local second = pool:Acquire(page)
        assert.are_not.equal(first, second)
        assert.equals(2, pool.created)
    end)

    it("orphans and counts a release that throws, at any step, and raises nothing", function()
        local page = fakeFrame(0, 0)
        local cases = {
            { name = "reset throws", resetThrows = true },
            { name = "parking on the holder throws", parkThrows = true },
        }
        for _, case in ipairs(cases) do
            GUIFrame._poolStats.failed = 0
            _G.KE_GUI_ORPHAN_COUNT = 0
            local pool = GUIFrame:NewWidgetPool("spec:" .. case.name, function(holder)
                local f = fakeFrame(0, 0)
                f.parent = holder
                f._keOwned = { f }
                local setParent = f.SetParent
                function f:SetParent(p)
                    if case.parkThrows and p ~= nil and p ~= page then error("park") end
                    setParent(self, p)
                end
                return f
            end, function()
                if case.resetThrows then error("reset") end
            end)

            local obj = pool:Acquire(page)
            assert.has_no.errors(function() pool:Release(obj) end, case.name)
            assert.equals("retired", obj._keState, case.name)
            assert.is_nil(obj.parent, case.name)
            assert.equals(1, GUIFrame._poolStats.failed, case.name)
            assert.equals(1, _G.KE_GUI_ORPHAN_COUNT, case.name)
            assert.equals(0, #pool.free, case.name)
        end
    end)

    it("pools only under the live scroll child, an in-use pooled card's content, or an in-use pooled row", function()
        local scrollChild = {}
        GUIFrame.contentArea = { scrollChild = scrollChild }
        local rowPool = { holdsWidgets = true }
        local leafPool = { holdsWidgets = false }
        local cases = {
            { name = "page scroll child",     parent = scrollChild, pooled = true },
            { name = "pooled card content",   parent = { _kePoolOwner = { _kePool = leafPool, _keState = "used" } }, pooled = true },
            { name = "pooled row",            parent = { _kePool = rowPool, _keState = "used" }, pooled = true },
            { name = "pooled leaf widget",    parent = { _kePool = leafPool, _keState = "used" }, pooled = false },
            { name = "released row",          parent = { _kePool = rowPool, _keState = "free" }, pooled = false },
            { name = "released card content", parent = { _kePoolOwner = { _kePool = leafPool, _keState = "free" } }, pooled = false },
            { name = "kit card content",      parent = { _kePoolOwner = {} }, pooled = false },
            { name = "untagged frame",        parent = {}, pooled = false },
            { name = "no parent",             parent = nil, pooled = false },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.pooled, GUIFrame:IsPoolParent(case.parent), case.name)
        end
    end)

    it("gives a row one label for its whole use and still releases the row clean", function()
        local labels = 0
        mock.install({ CreateFrame = function(_, _, parent)
            local f = fakeFrame(0, 0)
            f.parent = parent
            function f:SetScript() end
            function f:SetHeight() end
            function f:EnableMouse() end
            function f:CreateFontString()
                self.regions = self.regions + 1
                labels = labels + 1
                return setmetatable({}, { __index = function() return function() end end })
            end
            return f
        end })
        _G.UIParent = fakeFrame(0, 0)
        local KE = {
            Theme = { headerHeight = 32, borderSize = 1 },
            Print = function() end,
            ApplyThemeFont = function() end,
        }
        helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
        local G = KE.GUIFrame
        local page = fakeFrame(0, 0)
        G.contentArea = { scrollChild = page }

        local row = G:CreateRow(page, 24)
        local label = row:GetLabel("small")
        assert.equals(label, row:GetLabel("normal"))
        assert.equals(1, labels)

        G:ReleaseTracked(row, page)
        assert.equals("free", row._keState)
        assert.equals(0, G._poolStats.retired)
    end)
end)

describe("GUI-Core deferred widget callbacks", function()
    local GUIFrame, timers, rebuilt

    before_each(function()
        timers = {}
        mock.install({ C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end } })
        local KE = { Theme = { headerHeight = 32, borderSize = 1 }, Print = function() end }
        helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
        GUIFrame = KE.GUIFrame
        rebuilt = 0
        GUIFrame.contentRebuildCallbacks = { function() rebuilt = rebuilt + 1 end }
        GUIFrame.contentArea = {}
        GUIFrame.mainFrame = { IsShown = function() return true end }
    end)

    after_each(function() mock.reset() end)

    it("runs every pending call once, in order, at a rebuild, absorbs the rebuild they ask for, and leaves the timers idle", function()
        local ran = {}
        local function commit() ran[#ran + 1] = "commit" end
        GUIFrame:DeferWidgetCallback(0.18, function()
            ran[#ran + 1] = "clicked"
            GUIFrame:DeferWidgetCallback(0.18, function() ran[#ran + 1] = "queued while draining" end)
            GUIFrame:RefreshContent()
        end)
        -- The same function twice: two calls, two commits.
        GUIFrame:DeferWidgetCallback(0.18, commit)
        GUIFrame:DeferWidgetCallback(0.18, commit)

        -- Everything past the rebuild callbacks is real frame work and throws
        -- against these stubs, as in gui_minimize_refresh_spec.
        pcall(GUIFrame.RefreshContent, GUIFrame)

        assert.same({ "clicked", "commit", "commit", "queued while draining" }, ran)
        assert.equals(1, rebuilt, "only the outer rebuild ran")
        for _, fire in ipairs(timers) do fire() end
        assert.equals(4, #ran, "the timers found nothing left to run")
    end)

    it("refuses a rebuild asked for from inside its own teardown", function()
        local scrollChild = {}
        local asked = false
        local child = {
            GetParent = function() return scrollChild end,
            IsObjectType = function() return true end,
            SetParent = function() end,
            Hide = function()
                if asked then return end
                asked = true
                GUIFrame:RefreshContent()
            end,
        }
        function scrollChild:GetRegions() end
        function scrollChild:GetChildren() return child end
        GUIFrame.contentArea = { scrollChild = scrollChild }

        -- Everything past the teardown is real frame work and throws against
        -- these stubs.
        pcall(GUIFrame.RefreshContent, GUIFrame)

        assert.is_true(asked)
        assert.equals(1, rebuilt, "the nested call started no second rebuild")
        assert.is_nil(GUIFrame._tearingDown)
    end)
end)
